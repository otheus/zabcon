#!/usr/bin/ruby

#GPL 2.0  http://www.gnu.org/licenses/gpl-2.0.html
#Zabbix CLI Tool and associated files
#Copyright (C) 2009,2010 Andrew Nelson nelsonab(at)red-tux(dot)net
#
#This program is free software; you can redistribute it and/or
#modify it under the terms of the GNU General Public License
#as published by the Free Software Foundation; either version 2
#of the License, or (at your option) any later version.
#
#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.
#
#You should have received a copy of the GNU General Public License
#along with this program; if not, write to the Free Software
#Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

##########################################
# Subversion information
# $Id$
# $Revision$
##########################################

#setup our search path or libraries
ZABCON_PATH=File.expand_path(File.join(File.dirname(__FILE__), '.'))
$LOAD_PATH<<File.expand_path(File.dirname(__FILE__))

begin
  require 'rubygems'
rescue LoadError
  puts
  puts "Ruby Gems failed to load.  Please install Ruby Gems using your systems"
  puts "package management program or download it from http://rubygems.org."
  puts
  exit 1
end

#External Gems which are required for Zabcon.
REQUIRED_RUBY_VER="1.8.6"
DEPENDENCIES={
  "parseconfig"=>true,
  "json"=>true,
  "highline"=>true
}

if Gem::Version.create(RUBY_VERSION.dup) < Gem::Version.create(REQUIRED_RUBY_VER)
  puts "Zabcon requires Ruby version #{REQUIRED_RUBY_VER} or higher."
  puts "you are using Ruby version #{RUBY_VERSION}."
  puts
  exit(1)
end

depsok=true  #assume we will not fail dependencies

DEPENDENCIES.each do |pkg,ver|
  begin
    require pkg
    if ver.is_a?(Gem::Version) && Gem.loaded_specs[pkg].version<ver
      depsok=false
      puts "Error: '#{pkg}' must be at least version #{ver.to_s} or higher, #{Gem.loaded_specs[pkg].version.to_s} installed"
    end
  rescue LoadError
    depsok=false
    puts "Error: '#{pkg}' is a missing required dependency"
  end
end

#Test to see that Zbxapi is available
ZBXAPI_GEM="0.2.412"

begin
  require 'zbxapi'
  if Gem.loaded_specs['zbxapi'].version<Gem::Version.new(ZBXAPI_GEM)
    puts "Error: 'zbxapi' must be at least version #{ZBXAPI_GEM} or higher, #{Gem.loaded_specs['zbxapi'].version.to_s} installed"
    depsok=false
  end
rescue LoadError
  puts "Error: 'zbxapi' is required and missing."
  depsok=false
rescue NoMethodError
  puts "Using locally found gem, no version guarantees."
end

exit(1) if !depsok


require 'libs/utility_items'
require 'libs/revision'
require 'optparse'
require 'ostruct'
require 'strscan'
require 'zbxapi/zdebug'
require 'libs/zabcon_globals'
require 'parseconfig'

#Make any changes to base classes which are version specific
case Gem::Version.create(RUBY_VERSION.dup)
  when Gem::Version.create("1.8.6")
    #Ruby 1.8.6 lacks the each_char function in the string object, so we add it here
    String.class_eval do
      def each_char
        if block_given?
          scan(/./m) do |x|
            yield x
          end
        else
          scan(/./m)
        end
      end
    end
end

class ZabconApp

  def initialize
    setup_opt_parser
  end

  def setup_opt_parser
    @cmd_opts=OpenStruct.new
#    @options.debug=0

    @opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options] [command file]"
      opts.separator "------------------------------------"
      opts.separator ""
      opts.separator "If command file is specified Zabcon will read from the file"
      opts.separator "line by line and execute the commands in order.  If '-' is "
      opts.separator "used, Zabcon will read from stdin as though it were a file."
      opts.separator ""
      opts.separator "Options"
      opts.on("-h", "-?", "--help", "Display this help message") do
        @cmd_opts.echo=false
        @cmd_opts.help=true
        puts opts
      end
      opts.on("-l", "--load FILE", "load configuration file supplied or ","search the following default paths",
              "./zabcon.conf, ~/zabcon.conf in that","order") do |file|
        @cmd_opts.config_file=file
      end
      opts.on("--no-login", "Do not automatically log into Zabbix server on startup") do
        @cmd_opts.no_login=true
      end
      opts.on("-S","--use-server SERVER","Log into the named server from the config file on startup") do |server|
        @cmd_opts.default_server=server
      end
      opts.on("--no-config", "Do not attempt to automatically load","the configuration file") do
        @cmd_opts.load_config=false
      end
      opts.on("-d", "--debug LEVEL", Integer, "Specify debug level (Overrides config","file)") do |level|
        @cmd_opts.debug=level
      end
      opts.on("-s","--session PATH","Path to the file to store session information.") do |session|
        @cmd_opts.session_file=session
      end
      opts.on("--no-session","Disable checking of the session file on startup") do
        @cmd_opts.session_file=""
      end
      opts.on("-e", "--[no-]echo", "Enable startup echo.  Default is on ","for interactive") do |echo|
        @cmd_opts.echo=echo
      end
      opts.on("-s", "--separator CHAR", "Separator character for csv styple output.",
              "Use \\t for tab separated output.") do |sep|
        @cmd_opts.table_separator=sep
      end
      opts.on("--no-header", "Do not show headers on output.") do
        @cmd_opts.table_header=false
      end
    end
  end

  def setup_globals
#    env=EnvVars.instance  # we must instantiate a singleton before using it
    vars=GlobalVars.instance

    env["debug"]=0
    env["show_help"]=false
    env["server"]=nil
    env["username"]=nil
    env["password"]=nil
    env["proxy_server"]=nil
    env["proxy_port"]=3128
    env["proxy_user"]=nil
    env["proxy_password"]=nil
    env["lines"]=24
    env["language"]="english"
    env["logged_in"]=false
    env["have_tty"]=STDIN.tty?
    env["echo"]=STDIN.tty? ? true: false
    env["config_file"]=:default
    env["load_config"]=true
    env["truncate_length"]=5000
    env["custom_commands"]=nil
    env["session_file"]="~/zabcon.session"
    env["default_server"]="global"

    #output related environment variables
    env["table_output"]=STDIN.tty?   # Is the output a well formatted table, or csv like?
    env["table_header"]=true
    env["table_separator"]=","

  end
  #overrides is a hash of options which will override what is found in the config file.
  #useful for command line options.
  #if there is a hash called "config_file" this will override the default config file.
  def load_config(overrides={})
    begin
      config_file = overrides["config_file"] || env["config_file"]

      if config_file==:default
        home_default=File::expand_path("~/zabcon.conf")
        if File::exists?("zabcon.conf")
          config_file="zabcon.conf"
        elsif File::exists?(home_default)
          config_file=home_default
          env["config_file"]=home_default
        else
          raise "NoConfig"
        end
      end

      config = overrides["load_config"]==false ?   # nil != false
          {} : ParseConfig.new(config_file).params

      # If we are not loading the config use an empty hash
    rescue Errno::EACCES
      if !(config_file=="zabcon.conf" and !File::exists?(config_file))
        puts "Unable to access configuration file: #{config_file}"
      end
      config={}
    rescue RuntimeError=>e
      if e.message=="NoConfig"
        puts "Unable to find a default configuration file"
        env["no_login"]=true  #Do not attempt to log into a server, we have no config
        config={}
      else
        raise e
      end
    end

    config.merge!(overrides)  # merge the two option sets together but give precedence
                              # to command line options

    server_keys=["server","username","password","proxy_server",
                "proxy_port","proxy_user","proxy_password"]

    if !config.empty?
      ServerCredentials.instance["global"]=config.select_keys(server_keys).merge({"name"=>"global"})
      config.delete_keys(server_keys)
    end

    config.each_pair { |k,v|
      if k.match(/(.+)\[(.+)\]\[(.+)\]/)
        if $1.downcase=="server"
          ServerCredentials.instance[$2] ||= {"name"=>$2}
          ServerCredentials.instance[$2].merge!($3=>v)
        else
          env[$1] ||= {}
          env[$1][$2] ||= {}
          env[$1][$2].merge({$3=>v})
        end
      else
        env[k]=v
      end
    }

  end


  #checks to ensure all dependencies are available, forcefully exits with an
  # exit code of 1 if the dependency check fails
  # * ruby_rev is a string denoting the minimum version of ruby suitable
  # * *dependencies is an array of libraries which are required

  def run
    begin
      setup_globals          # step 1, set up the global environment variables
      @opts.parse!(ARGV)     # step 2, parse the command line and setup the class variable @cmd_opts

      h = @cmd_opts.marshal_dump()  #dump the hash to a temporary variable
      cmd_hash={}
      h.each_pair do |k,v|
        cmd_hash[k.to_s]=v
      end

      load_config(cmd_hash)

    rescue OptionParser::InvalidOption  => e
      puts e
      puts
      puts @opts
      exit(1)
    rescue OptionParser::InvalidArgument => e
      puts e
      puts
      puts @opts
      exit(1)
    rescue OptionParser::MissingArgument => e
      puts e
      puts
      puts @opts
      exit(1)
    end

    puts RUBY_PLATFORM if EnvVars.instance["echo"]

    begin
      require 'readline'
    rescue LoadError
      puts "Readline support was not compiled into Ruby.  Readline support is required."
      exit
    end

    #If we don't have the each_char method for the string class include the module that has it.
    if !String.method_defined?("each_char")
      begin
        require 'jcode'
      rescue LoadError
        puts "Module jcode is required for your version of Ruby"
      end
    end

    require 'libs/zabcon_core'   #Require placed after deps check

    if @cmd_opts.help.nil?
      zabcon=ZabconCore.new
      zabcon.start()
    end
  end
end

begin
  zabconapp=ZabconApp.new()
  zabconapp.run()
rescue Exception => e
  puts "Runtime error detected"
  puts "(#{e.class}): #{e.message}"
  puts
  puts "Top 10 items in backtrace"
  n=1
  e.backtrace.first(10).each {|i|
    puts "#{n}: #{i}"
    n+=1
  }
end

