#!/usr/bin/ruby

#GPL 2.0  http://www.gnu.org/licenses/gpl-2.0.html
#Zabbix CLI Tool and associated files
#Copyright (C) 2009 Andrew Nelson nelsonab(at)red-tux(dot)net
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
# $Id: zabcon.rb 93 2009-10-23 09:40:24Z nelsonab $
# $Revision: 93 $
##########################################

require 'rubygems'
require 'parseconfig'
require 'optparse'
require 'ostruct'
require 'rexml/document'
require 'cli_libs/zbxcliserver'
require 'cli_libs/printer'
require 'cli_libs/debug'
require 'cli_libs/input'
require 'cli_libs/defines'
require 'cli_libs/command_tree'

class ZabconCore

  include ZDebug

  def initialize(options)
    set_debug_level(options.debug)   # this must come first as the debug module will throw an error
                    # if this variable is not initialized
    @server = nil
    @callbacks={}
    @printer=OutputPrinter.new
    @commands=nil
    if options.configfile.nil?
      @conffile="zabcon.conf"
    else
      @conffile=options.configfile
      do_load_config(nil)
    end
    @debug_prompt=false
    if STDIN.tty?
      prc=Proc.new do
        debug_part = @debug_prompt ? " #{debug_level}" : ""
        if @server.nil?
          " #{debug_part}-> "
        else
          @server.login? ? " #{debug_part}+> " : " #{debug_part}-> "
        end
      end
      @input=Rawline_Input.new
      @input.set_prompt_func(prc)
    else
      @input=STDIN_Input.new
    end
  end

  # Argument logged in is used to determine which set of commands to load.  If loggedin is true then commands which
  # require a valid login are loaded
  def setupcommands(loggedin)

    @commands=Parser.new

    # These commands do not require a valid login
    @commands.insert "", "quit", :exit
    @commands.insert "", "exit", :exit
    @commands.insert "", "help", self.method(:do_help)
    @commands.insert "", "login", self.method(:do_login)
    @commands.insert "", "load", nil
    @commands.insert "load", "config", self.method(:do_load_config)
    @commands.insert "", "info", self.method(:do_info)
    @commands.insert "", "hisotry", self.method(:do_history)
    @commands.insert "", "set", nil
    @commands.insert "set", "debug", self.method(:set_debug)
    @commands.insert "set", "lines", self.method(:set_lines)
    @commands.insert "set", "pause", self.method(:set_pause)
    

    if loggedin then
      # These commands do require a valid login
      @commands.insert "", "get", nil
      @commands.insert "", "add", nil
      @commands.insert "", "delete", nil
      @commands.insert "", "update", nil
      @commands.insert "", "import", self.method(:do_import)

      @commands.insert "get", "user", @server.method(:getuser)
      @commands.insert "add", "user", @server.method(:adduser)
      @commands.insert "delete", "user", @server.method(:deleteuser)
      @commands.insert "update", "user", @server.method(:updateuser)
      @commands.insert "add user", "media", @server.method(:addusermedia)
      @commands.insert "get", "host", @server.method(:gethost)
      @commands.insert "add", "host", @server.method(:addhost)
      @commands.insert "get", "item", @server.method(:getitem)
      @commands.insert "get host", "group", @server.method(:gethostgroup)
      @commands.insert "get", "app", @server.method(:getapp)
      @commands.insert "add", "app", @server.method(:addapp)
      @commands.insert "add app", "id", @server.method(:getappid)
      @commands.insert "get", "trigger", @server.method(:gettrigger)
      @commands.insert "add", "trigger", @server.method(:addtrigger)
      @commands.insert "add", "link", @server.method(:addlink)
      @commands.insert "add", "sysmap", @server.method(:addsysmap)
      @commands.insert "add sysmap", "element", @server.method(:addelementtosysmap)
      @commands.insert "get", "seid", @server.method(:getseid)
      @commands.insert "add link", "trigger", @server.method(:addlinktrigger)
      @commands.insert "get host group", "id", @server.method(:gethostgroupid)
      @commands.insert "add host", "group", @server.method(:addhostgroup)
    end

  end

  def start
    puts "Welcome to Zabcon."
    puts "Use the command 'help' to get help on commands"

#    setupcallbacks
    setupcommands(!@server.nil?)  # If we don't have a valid server we're not logged in'
    begin
      while line=@input.get_line()
        debug(6, line, "Input from user")
        rhash=@commands.parse(line)
        debug(6, rhash, "Results from parse")

        next if rhash.nil?
        break if rhash[:proc]==:exit

        # Do some special argument processing
        # We may get rid of this if the commands class get's a validator function
        if !rhash[:args].nil?
          rhash[:args]["extendoutput"]=true if rhash[:args]["show"]=="all"  
        end

        if !rhash[:proc].nil?
          debug(4,rhash,"Calling function",250)
          results=rhash[:proc].call(rhash[:args])

          # Before we can print we must do some stuff with the arguments
          # If the show argument was used we need to pass it's parameters
          showparams= rhash.nil? ? nil : rhash[:args]["show"]
          
          @printer.print(results,showparams) if !results.nil?
        end

#        rhash = @parser.parse_input(line)
#        debug(5, rhash, "Parsed input loop start")
#        if !rhash.nil? and !rhash[:command].nil?
#          if rhash[:command]==:quit or rhash[:command]==:exit then
#            break
#          elsif !(cmd=@callbacks[rhash[:command]]).nil? then
#            flags=cmd[:flags]
#            if !flags.nil? then
#              #do flag checking here
#            end
#            args = nil
#            params = rhash[:parameters]
#            if !params.nil? then
#              args=params.clone
#              if !params["show"].nil? then
#                args["extendoutput"]=true
#                args.delete("show")
#              end
#            end
#
#            # We use the flag :output to determine if the function requires output or not
#            # when moving to the new command tree perhaps get rid of the output flag and assume all functions return
#            # some form of valid output
#            if flags.nil? or flags[:output].nil? then
#              cmd[:proc].call(args)
#            else
#              result=cmd[:proc].call(args)
#              params=params["show"] if !params.nil?
#              @printer.print(result,params)
#            end
#          else
#            puts "Error: not logged in"
#          end
#        end
      end
    rescue ZbxAPI_ExceptionVersion => e
      puts e
      retry  # We will allow for graceful recover from Version exceptions
    rescue ZbxAPI_GeneralError => e
      puts "An error was received from the Zabbix server"
      if e.message.class==Hash
        puts "Error code: #{e.message["code"]}"
        puts "Error message: #{e.message["message"]}"
        puts "Error data: #{e.message["data"]}"
      else
        puts "Error: #{e.message}"
      end
    rescue CLIParseError => e
      puts "Error: #{e.message}"
    end  #end of exception block
  end

  def getprompt
  debug_part = @debug_prompt ? " #{debug_level}" : ""
  if @server.nil?
      return " #{debug_part}-> "
  end
    return @server.login? ? " #{debug_part}+> " : " #{debug_part}-> "
  end

  def do_help(input)
  puts <<here_document
General help
Prompt
The prompt has the following format "XXs >"
XX = number representing the current debug level, one or two digits
s = + or - symbol representing current login state.
    + represents a current login

Command help
<>  Mandatory argument/command
()  Optional argument/command

help             - Show this help list
info              - show information about current state
exit              - quit
quit              - quit
history           - Show current history list
login <server> <username> <password>
                  - server is a fully qualified url
load configuration <config file>
                  - loads configuration settings from a file and logs
                    into server
get user          - returns a list of all users
get host          - returns a list of hosts
get item          - returns a list of items
  hostids=<num>   - returns a list of items for host
  extendoutput=true
                  - displays more information
import <file>     - Import configuration from an XML file
set <command>     - Sets various variables
  debug <num>     - Sets the debug level to <num>
  prompt          - Prompt related commands
    debug <1/0>   - Turn the debug portion of the prompt on or off
  lines <num>     - Set the screen height.  0 turns off Screen pausing
add user          - Adds a user to Zabbix
                  - without parameters causes help message to be displayed
delete user <num> - Deletes user with uid=num

Zabcon Copyright (C) 2009 Andrew Nelson.  Zabcon comes with ABSOLUTELY NO
WARRANTY; for details see the text of the GNU General Public License 2.0
at http://www.gnu.org/licenses/gpl-2.0.html
here_document
  end

  def do_history(input)
    history = @input.history.to_a
    history.each_index do |index|
      puts "#{index}: #{history[index]}"
    end
  end

  def setdebuglevel(level)
    set_debug_level(level)
    @server.debuglevel=level if !@server.nil?
  end

  # set_debug is for the callback to set the debug level
  def set_debug(input)
      if input["prompt"].nil? then
      setdebuglevel(input.keys[0].to_i)
    else
      @debug_prompt=!@debug_prompt
    end
  end

  def set_lines(input)
    @printer.sheight=input.keys[0].to_i
  end

  def set_pause(input)
    if input.nil? then
      puts "set pause requires either Off or On"
      return
    end
    
    if input.keys[0].upcase=="OFF"
      @printer.sheight=@printer.sheight.abs*(-1)
    elsif input.keys[0].upcase=="ON"
      @printer.sheight=@printer.sheight.abs
    else
      puts "set pause requires either Off or On"
    end
    @printer.sheight = 24 if @printer.sheight==0
  end

#  def do_set(input)
#    case input["type"]
#      when 'debug'
#        set_debug_level(input["level"])
#        @server.debuglevel=input["level"] if !@server.nil?
#      when 'prompt-debug-toggle'
#        @debug_prompt=(input["debug-toggle"]!=0)
#    end
#  end

  def do_load_config(params)
    debug(6,params)
    
    # if nil use @conffile
    # if empty use @conffile
    # else use passed in value
    fname=params.nil? ? @conffile : fname=params.empty? ? @conffile : params[:filename]
    
    begin
      config=ParseConfig.new(fname).params
      debug(1,config)
      if !config["server"].nil? and !config["username"].nil? and !config["password"].nil? then
        do_login({:server=>config["server"], :username=>config["username"],
          :password=>config["password"]})
      else
        puts "Missing one of the following, server, username or password or bad syntax"
      end

      if !config["lines"].nil?
        @printer.sheight=config["lines"].to_i
      end

      if !config["debuglevel"].nil?
        setdebuglevel(config["debuglevel"].to_i)
      end

    rescue Errno::EACCES
      puts "Unable to open file #{fname}"
    end
  end

  def do_login(params)
    url = params[:server]
    username = params[:username]
    password = params[:password]

    begin
      @server = ZbxCliServer.new(url,username,password,debug_level)
      puts "#{url} connected"
      puts "API Version: #{@server.version}"

      return true
    rescue ZbxAPI_ExceptionBadAuth
      puts "Login error, incorrect login information"
      puts "Server: #{url}   User: #{username}  password: #{password}"   # will need to remove password in later versions
      return false
    rescue ZbxAPI_ExceptionBadServerUrl
      puts "Login error, unable to connect to host or bad host name: '#{url}'"
#    rescue ZbxAPI_ExceptionConnectionRefused
#      puts "Server refused connection, is url correct?"
    end
  end

  def do_info(input)
    puts "Current settings"
    puts "Server"
    if @server.nil?
      puts "Not connected"
    else
      puts " Server Name: %s" % @server.server_url
      puts " Username: %-15s Password: %-12s" % [@server.user, Array.new(@server.password.length,'*')]
    end
    puts "Display"
    puts " Current screen length #{@printer.sheight}"
    puts "Other"
    puts " Debug level %d" % @@debug_level
  end

#
# Import config from an XML file:
#
  def do_import(input)
    if input.nil?
      puts "Run requires a file name as argument."
      return
    end

    begin
      xml_import = REXML::Document.new File.new(input[:filename])
    rescue Errno::ENOENT
      puts "Failed to open import file #{input[:filename]}."
      return
    end

    if xml_import.nil?
      puts "Failed to parse import file #{input[:filename]}."
      return
    end

    host=xml_import.elements['import/hosts']
    if !host.nil?
      host = host[1]
    end

    # Loop for the host tags:
    while !host.nil?
      host_params = { 'host' => host.attributes["name"],
                 'port' => host.elements["port"].text }
      if host.elements["useip"].text.to_i == 0 # This is broken in Zabbix export (always 0).
        host_params['dns']=host.elements["dns"].text
      else
        host_params['ip']=host.elements["ip"].text
      end
      # Loop through the groups:
      group = host.elements['groups/']
      if !group.nil?
        group = group[1]
      end
      groupids = Array.new
      while !group.nil?
        result = @server.gethostgroupid({ 'name' => group.text })
        groupid = result[:result].to_i
        if groupid == 0
          puts "The host group " + group.text + " doesn't exist. Attempting to add it."
          result = @server.addhostgroup(['name' => group.text])
          groupid = result[:result].to_a[0][1].to_i
          if groupid == 0
            puts "The group \"" + group.text + "\" doesn't exist and couldn't be added. Terminating import."
            return
          end
        end
        groupids << groupid
        group = group.next_element
      end
      host_params['groupids'] = groupids;

      # Add the host
      result = @server.addhost(host_params)[:result]
      hostid = @server.gethost( { 'pattern' => host.attributes['name'] } )[:result].to_a[0][1]
      if result.nil? # Todo: result is nil when the host is added. I'm not sure if I buggered it up or not.
        puts "Added host " + host.attributes['name'] + ": " + hostid.to_s
      else
        puts "Failed to add host " + host.attributes['name']
      end

      # Item loop (within host loop)
      item = host.elements['items/']
      if !item.nil?
        item = item[1]
        item_params = Array.new
        appids = Array.new
        while !item.nil?
          # Application loop:
          app = item.elements['applications/']
          if !app.nil?
            app = app[1]
            if hostid != 0
              while !app.nil?
                appid = @server.getappid({'name' => app.text, 'hostid' => hostid})[:result]
                if appid == 0
                  result = @server.addapp([{'name' => app.text, 'hostid' => hostid}])
                  appid = result[:result].to_a[0][1].to_i
                  puts "Application " + app.text + " added: " + appid.to_s
                end
                appids << appid
                app = app.next_element
              end
            else
              puts "There is no hostname associated with the application " + app.text
              puts "An application must be associated with a host. It has not been added."
            end
          end

          item_params = { 'description'           => item.elements["description"].text,
                          'key_'                  => item.attributes["key"],
                          'hostid'                => hostid,
                          'delay'                 => item.elements['delay'].text.to_s.to_i,
                          'history'               => item.elements['history'].text.to_s.to_i,
                          'status'                => item.elements['status'].text.to_s.to_i,
                          'type'                  => item.attributes['type'].to_i,
                          'snmp_community'        => item.elements['snmp_community'].text.to_s,
                          'snmp_oid'              => item.elements['snmp_oid'].text.to_s,
                          'value_type'            => item.attributes['value_type'].to_i,
                          'data_type'             => item.elements['data_type'].text.to_s.to_i,
                          'trapper_hosts'         => 'localhost',
                          'snmp_port'             => item.elements['snmp_port'].text.to_s.to_i,
                          'units'                 => item.elements['units'].text.to_s,
                          'multiplier'            => item.elements['multiplier'].text.to_s.to_i,
                          'delta'                 => item.elements['delta'].text.to_s.to_i,
                          'snmpv3_securityname'   => item.elements['snmpv3_securityname'].text.to_s,
                          'snmpv3_securitylevel'  => item.elements['snmpv3_securitylevel'].text.to_s.to_i,
                          'snmpv3_authpassphrase' => item.elements['snmpv3_authpassphrase'].text.to_s,
                          'snmpv3_privpassphrase' => item.elements['snmpv3_privpassphrase'].text.to_s,
                          'formula'               => item.elements['formula'].text.to_s.to_i,
                          'trends'                => item.elements['trends'].text.to_s.to_i,
                          'logtimefmt'            => item.elements['logtimefmt'].text.to_s,
                          'valuemapid'            => 0,
                          'delay_flex'            => item.elements['delay_flex'].text.to_s,
                          'params'                => item.elements['params'].text.to_s,
                          'ipmi_sensor'           => item.elements['ipmi_sensor'].text.to_s.to_i,
                          'applications'          => appids,
                          'templateid'            => 0 }
          added_item = @server.additem([item_params])
          puts "Added item " + item.elements["description"].text + ": " + added_item[0]
          item = item.next_element
        end # End of item loop (within host loop)
      end

      host = host.next_element
    end # End of loop for host tags

    # Trigger loop
    trigger=xml_import.elements['import/triggers']
    if !trigger.nil?
      trigger = trigger[1]
    end
    while !trigger.nil?
      trigger_params = { 'description' => trigger.elements['description'].text,
                         'type'        => trigger.elements['type'].text.to_i,
                         'expression'  => trigger.elements['expression'].text,
                         'url'         => '', # trigger.elements['url'].text,
                         'status'      => trigger.elements['status'].text.to_i,
                         'priority'    => trigger.elements['priority'].text.to_i,
                         'comments'     => 'No comments.' } # trigger.elements['comments'].text }
      result = @server.addtrigger( trigger_params )
      puts "Added trigger " + result[:result][0]['triggerid'] + ": " + trigger.elements['description'].text
      trigger = trigger.next_element
    end

    # Sysmap loop
    sysmap = xml_import.elements['import/sysmaps/']
    if !sysmap.nil?
      sysmap = sysmap[1]
    end
    while !sysmap.nil?
      sysmap_params = { 'name' => sysmap.attributes['name'],
                        'width' => sysmap.elements['width'].text.to_i,
                        'height' => sysmap.elements['height'].text.to_i,
                        'backgroundid' => sysmap.elements['backgroundid'].text.to_i,
                        'label_type' => sysmap.elements['label_type'].text.to_i,
                        'label_location' => sysmap.elements['label_location'].text.to_i }
      sysmapid = 0
      result = @server.addsysmap([sysmap_params])
      # Get sysmapid from the result code
      sysmapid = result[:result][0]['sysmapid'].to_i
      puts "Added sysmap " + sysmap.attributes['name'] + ": " + sysmapid.to_s

      if sysmapid != 0 # We must have a sysmap ID to add elements

        # Element loop (within the sysmap loop)
        element = sysmap.elements['/import/sysmaps/sysmap/elements/']
        if !element.nil?
          element = element[1]
        end
        while !element.nil?
          # Todo: change to use case.
          elementtype = element.elements['elementtype'].text.to_i
          if elementtype != ME_IMAGE
            hostid = @server.gethost( { 'pattern' => element.elements['hostname'].text } )[:result].to_a[0][1].to_i
          end
          if elementtype == ME_HOST
            elementid = hostid
          elsif elementtype == ME_TRIGGER
            elementid = @server.gettrigger({'hostids' => hostid, 'pattern' => element.elements['tdesc'].text})
            elementid = elementid[:result].to_a[0][1].to_i
          else # ME_IMAGE for now.
            elementid = 0
          end
          element_params = { 'label' => element.attributes['label'],
                             'sysmapid' => sysmapid,
                             'elementid' => elementid,
                             'elementtype' => element.elements['elementtype'].text.to_i,
                             'iconid_off' => element.elements['iconid_off'].text.to_i,
                             'iconid_on' => element.elements['iconid_on'].text.to_i,
                             'iconid_unknown' => element.elements['iconid_unknown'].text.to_i,
                             'iconid_disabled' => element.elements['iconid_disabled'].text.to_i,
                             'label_location' => element.elements['label_location'].text.to_i,
                             'x' => element.elements['x'].text.to_i,
                             'y' => element.elements['y'].text.to_i }
                             # 'url' => element.elements['url'].text }
          result = @server.addelementtosysmap([element_params])
          puts "Added map element " + element.attributes['label'] + ": " + result[:result]
          element = element.next_element
        end # End of element loop (within the sysmap loop)

        # Sysmap link loop (within the sysmap loop)
        syslink = sysmap.elements['/import/sysmaps/sysmap/sysmaplinks/']
        if !syslink.nil?
          syslink = syslink[1]
        end
        while !syslink.nil?
          # The code down to "link_params = {" is a mess and needs to be rewritten.
          # elementid = hostid or triggerid depending on element type.
          if syslink.elements['type1'].text.to_i == ME_HOST
            hostid1 = @server.gethost( { 'pattern' => syslink.elements['host1'].text } )[:result].to_a[0][1]
            selementid1 = @server.getseid({'elementid' => hostid1, 'sysmapid' => sysmapid})[:result].to_a[0][1].to_i
          elsif syslink.elements['type1'].text.to_i == ME_TRIGGER # The first element is a trigger
            hostid1 = @server.gethost( { 'pattern' => syslink.elements['host1'].text } )[:result].to_a[0][1]
            triggerid1 = @server.gettrigger({'hostids' => hostid1, 'pattern' => syslink.elements['tdesc1'].text})
            hostid1 = triggerid1[:result].to_a[0][1].to_i
            selementid1 = @server.getseid({'elementid' => hostid1, 'sysmapid' => sysmapid})[:result].to_a[0][1].to_i
          elsif syslink.elements['type1'].text.to_i == ME_IMAGE
            label = syslink.elements['label1'].text
            selementid1 = @server.getseid({'label' => label, 'sysmapid' => sysmapid})[:result].to_a[0][1].to_i
          end
          # The other end of the link:
          if syslink.elements['type2'].text.to_i == ME_HOST
            hostid2 = @server.gethost( { 'pattern' => syslink.elements['host2'].text } )[:result].to_a[0][1]
            selementid2 = @server.getseid({'elementid' => hostid2, 'sysmapid' => sysmapid})[:result].to_a[0][1].to_i
          elsif syslink.elements['type2'].text.to_i == ME_TRIGGER # The second element is a trigger
            hostid2 = @server.gethost( { 'pattern' => syslink.elements['host2'].text } )[:result].to_a[0][1]
            triggerid2 = @server.gettrigger({'hostids' => hostid2, 'pattern' => syslink.elements['tdesc2'].text})
            triggerid2 = triggerid2[:result].to_a[0][1].to_i
            selementid2 = @server.getseid({'elementid' => triggerid2, 'sysmapid' => sysmapid})[:result].to_a[0][1].to_i
          elsif syslink.elements['type2'].text.to_i == ME_IMAGE
            label = syslink.elements['label2'].text
            selementid2 = @server.getseid({'pattern' => label, 'sysmapid' => sysmapid})[:result].to_a[0][1].to_i
          end
          link_params = { 'sysmapid' => sysmapid,
                          'selementid1' => selementid1,
                          'selementid2' => selementid2,
                          'triggers' => [], # The triggers require linkid, so this is a catch 22
                          'drawtype' => syslink.elements['drawtype'].text.to_i,
                          'color' => syslink.elements['color'].text.tr('"','') }
          result = @server.addlink([link_params])
          linkid = result[:result].to_i
          puts "Link added: " + link_params.inspect
          #puts "Added map link " + linkid.to_s + " (" + syslink.elements['host1'].text + "(" +
          #     hostid1.to_s + ") <-> " + syslink.elements['host2'].text + "(" + hostid2.to_s + "))."

          if !linkid.nil? # Link triggers require the associated link
            # Sysmap link trigger loop (within the sysmap and syslink loop)
            linktrigger = syslink.elements['linktriggers/']
            if !linktrigger.nil?
              linktrigger = linktrigger[1]
            end
            i = 0
            linktrigger_params = Array.new
            while !linktrigger.nil?
              # Add hostname and tdesc field in the XML to identify the link:
              hostid = @server.gethost( { 'pattern' => linktrigger.elements['host'].text } )[:result].to_a[0][1].to_i
              triggerid = @server.gettrigger({'hostids' => hostid, 'pattern' => linktrigger.elements['tdesc'].text})
              triggerid = triggerid[:result].to_a[0][1].to_i
              if triggerid.nil?
                puts "Failed to find trigger for host " + host + " and description \"" + tdesc + "\"."
              else
                linktrigger_params[i] = { 'linkid' => linkid,
                                          'triggerid' => triggerid,
                                          'drawtype' => linktrigger.elements['drawtype'].text.to_i,
                                          'color' => linktrigger.elements['color'].text.tr('"', '') }
                i = i + 1
              end
              linktrigger = linktrigger.next_element
            end # End linktrigger loop (within sysmap and syslink loop)
              puts "Adding link trigger(s): " + linktrigger_params.inspect
              result = @server.addlinktrigger(linktrigger_params);
          end # If !linkid.nil? (linktrigger)

          syslink = syslink.next_element
        end # End syslink loop

      end # End If sysmap
      sysmap = sysmap.next_element
    end # End Sysmap loop

  end # end do_import

end #end class

class ZabconApp
  def initialize
    @options=OpenStruct.new
    @options.debug=0

    @opts = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"
      opts.separator "------------------------------------"
      opts.separator ""
      opts.separator "Options"
      opts.on("-h","--help","Display this help message") do
        @options.help=true
        puts opts
      end
      opts.on("-l","--load [file]","load configuration file supplied or default if none") do |file|
        if file.nil?
          @options.configfile="zabcon.conf"
        else
          @options.configfile=file
        end
      end
      opts.on("-d","--debug LEVEL",Integer,"Specify debug level") do |level|
        @options.debug=level
      end
    end
  end

  def run
#    p ARGV
    @opts.parse!(ARGV)
#    p @options
    if @options.help.nil?
      zabcon=ZabconCore.new(@options)
      zabcon.start()
    end
  end
end

if __FILE__ == $0

puts RUBY_PLATFORM
zabconapp=ZabconApp.new()
zabconapp.run()

end
