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

require 'libs/utility_items'
require 'libs/revision'
require 'parseconfig'
require 'ostruct'
require 'rexml/document'
require 'libs/zabbix_server'
require 'libs/printer'
require 'zbxapi/zdebug'
require 'libs/input'
#require 'libs/defines'
require 'libs/command_tree'
#require 'libs/argument_processor'
require 'libs/command_help'
require 'libs/zabcon_globals'
require 'libs/zabcon_commands'
require 'libs/lexer'



class ZabconCore

  include ZDebug


  def initialize()
    # This must be set first or the debug module will throw an error
    set_debug_level(env["debug"])

    env.register_notifier("debug",self.method(:set_debug_level))
    env.register_notifier("api_debug",self.method(:set_debug_api_level))

    @printer=OutputPrinter.new
    debug(5,:msg=>"Setting up help")
#    @cmd_help=CommandHelp.new("english")  # Setup help functions, determine default language to use
    CommandHelp.setup("english")

    #TODO Remove reference to ArgumentProcessor when new command objects in use
    debug(5,:msg=>"Setting up ArgumentProcessor")
#    @arg_processor=ArgumentProcessor.new  # Need to instantiate for debug routines

    if !env["server"].nil? and !env["username"].nil? and !env["password"].nil? then
      puts "Found valid login credentials, attempting login"  if env["echo"]
      begin
        ZabbixServer.instance.login

      rescue ZbxAPI_ExceptionBadAuth => e
        puts e.message
      rescue ZbxAPI_ExceptionLoginPermission
        puts "Error Invalid login or no API permissions."
      end
    end

    debug(5,:msg=>"Setting up prompt")
    @debug_prompt=false
    if env["have_tty"]
      prc=Proc.new do
        debug_part = @debug_prompt ? " #{debug_level}" : ""
        if !ZabbixServer.instance.connected?
          " #{debug_part}-> "
        else
          ZabbixServer.instance.loggedin? ? " #{debug_part}+> " : " #{debug_part}-> "
        end
      end
      @input=Readline_Input.new
      @input.set_prompt_func(prc)
    else
      @input=STDIN_Input.new
    end

###############################################################################
###############################################################################
    zabconcore=self
    if @input.respond_to?(:history)
      ZabconCommand.add_command "history" do
        set_method do  zabconcore.show_history end
        set_help_tag :history
      end
    else
      ZabconCommand.add_command "history" do
        set_method do puts "History is not supported by your version of Ruby and ReadLine" end
        set_help_tag :history
      end
    end
###############################################################################
###############################################################################

    debug(5,:msg=>"Setting up custom commands")

    if !env["custom_commands"].nil?
      filename=nil
      cmd_file=env["custom_commands"]
      filename=File.exist?(cmd_file) && cmd_file
      cmd_file=File::expand_path("~/#{env["custom_commands"]}")
      filename=File.exist?(cmd_file) && cmd_file if filename.class!=String
      if filename.class==String
        puts "Loading custom commands from #{filename}" if env["echo"]
        begin
          load filename
        rescue Exception=> e
          puts "There was an error loading your custom commands"
          p e
        end
      end
    end

    debug(5,:msg=>"Setup complete")
  end

#  #TODO The following method may need to be removed when new command object in use
#  # Argument logged in is used to determine which set of commands to load. If loggedin is true then commands which
#  # require a valid login are loaded
#  def setupcommands(loggedin)
#    debug(5,loggedin,"Starting setupcommands (loggedin)")
#
#
##    no_cmd=nil
##    no_args=nil
##    no_help=nil
##    no_verify=nil
#
#    login_required = lambda {
#      debug(6,"Lambda 'login_required'")
#      puts "Login required"
#      }
#
#    # parameters for insert:  insert_path, command, commandproc, arguments=[], helpproc=nil, verify_func=nil, options
#
#      #Import commented out until fixed
#      #@commands.insert ["import"], self.method(:do_import),no_args,@cmd_help.method(:import),@arg_processor.default,:not_empty, :use_array_processor, :num_args=>"==1"
#
#      @commands.insert ["add","app","id"], @server.method(:getappid),no_args,no_help,no_verify
#      @commands.insert ["add","link"], @server.method(:addlink),no_args,no_help,no_verify
#      @commands.insert ["add","link","trigger"], @server.method(:addlinktrigger),no_args,no_help,no_verify
#      @commands.insert ["add","sysmap"], @server.method(:addsysmap),no_args,no_help,no_verify
#      @commands.insert ["add","sysmap","element"], @server.method(:addelementtosysmap),no_args,no_help,no_verify
#      @commands.insert ["add","user","media"], @server.method(:addusermedia),no_args,@cmd_help.method(:add_user_media),no_verify
#
#      @commands.insert ["get","host","group","id"], @server.method(:gethostgroupid), no_args, no_help, @arg_processor.method(:get_group_id)
#      @commands.insert ["get","seid"], @server.method(:getseid), no_args, no_help, @arg_processor.default_get

  def start
    debug(5,:msg=>"Entering main zabcon start routine")
    puts "Welcome to Zabcon.  Build Number: #{REVISION}"  if env["echo"]
    puts "Use the command 'help' to get help on commands" if env["have_tty"] || env["echo"]

    begin
      catch(:exit) do
        while line=@input.get_line()
          tokens=ExpressionTokenizer.new(line)
          line=line.strip_comments
          next if line.nil?
          next if line.strip.length==0  # don't bother parsing an empty line'
          debug(6, :var=>line, :msg=>"Input from user")

          commands=ZabconExecuteContainer.new(tokens)
          debug(8,:var=>commands,:msg=>"Commands tree")

          commands.execute
          @printer.print(commands.results,commands.show_params) if commands.print?

        end  # while
      end #end catch
    rescue CommandList::InvalidCommand => e
      puts e.message
      retry
    rescue Command::NonFatalError => e
      puts e.message
      retry
    rescue Command::ParameterError => e
      puts e.message
      retry
    rescue ZabbixServer::ConnectionProblem => e
      puts e.message
      retry
    rescue ParseError => e  #catch the base exception class
      e.show_message
      retry if e.retry?
    rescue ZbxAPI_ExceptionVersion => e
      puts e
      retry  # We will allow for graceful recover from Version exceptions
    rescue ZbxAPI_ExceptionBadAuth => e
      puts e.message
      retry
    rescue ZbxAPI_ExceptionLoginPermission
      puts "No login permissions"
      retry
    rescue ZbxAPI_ExceptionPermissionError
      puts "You do not have permission to perform that operation"
      retry
    rescue ZbxAPI_GeneralError => e
      puts "An error was received from the Zabbix server"
      if e.message.class==Hash
        puts "Error code: #{e.message["code"]}"
        puts "Error message: #{e.message["message"]}"
        puts "Error data: #{e.message["data"]}"
        retry
      else
        e.show_message
        retry if e.retry?
      end
    rescue ZError => e
      puts
      if e.retry?
        puts "A non-fatal error occurred."
      else
        puts "A fatal error occurred."
      end
      e.show_message
      retry if e.retry?
    end  #end of exception block
  end # def

  def getprompt
  debug_part = @debug_prompt ? " #{debug_level}" : ""

  return " #{debug_part}-> " if @server.nil?
  @server.login? ? " #{debug_part}+> " : " #{debug_part}-> "
  end

#  def set_lines(input)
#    @printer.sheight=input.keys[0].to_i
#  end

#  def set_pause(input)
#    if input.nil? then
#      puts "set pause requires either Off or On"
#      return
#    end
#
#    if input.keys[0].upcase=="OFF"
#      @printer.sheight=@printer.sheight.abs*(-1)
#    elsif input.keys[0].upcase=="ON"
#      @printer.sheight=@printer.sheight.abs
#    else
#      puts "set pause requires either Off or On"
#    end
#    @printer.sheight = 24 if @printer.sheight==0
#  end

  def set_debug(input)
    if input["prompt"].nil? then
      puts "This command is deprecated, please use \"set env debug=n\""
      @env["debug"]=input.keys[0].to_i
    else
      @debug_prompt=!@debug_prompt
    end
  end

  def set_debug_api_level(value)
    puts "inside set_debug_api_level"
    set_facility_debug_level(:api,value)
  end

#  def set_var(input)
#    debug(6,input)
#    input.each {|key,val|
#      GlobalVars.instance[key]=val
#      puts "#{key} : #{val.inspect}"
#    }
#  end

#  def unset_var(input)
#    if input.empty?
#      puts "No variables given to unset"
#    else
#      input.each {|item|
#        if GlobalVars.instance[item].nil?
#          puts "#{item} *** Not Defined ***"
#        else
#          GlobalVars.instance.delete(item)
#          puts "#{item} Deleted"
#        end
#      }
#    end
#  end

#
# Import config from an XML file:
#
  def do_import(input)
    debug(5,:var=>input,:msg=>"args")

    input=input[0]

    begin
      xml_import = REXML::Document.new(File.new(input)).root
    rescue Errno::ENOENT
      raise ZabconError.new("Failed to open import file #{input}.",:retry=>true)
    end

    if xml_import.nil?
      raise ZabconError.new("Failed to parse import file #{input}.",:retry=>true)
    end

    p hosts=xml_import.elements.to_a("//hosts")[0]
    p hosts = hosts.elements.to_a("//host")
    if !hosts.empty?
      host = hosts[0]
    end

    # Loop for the host tags:
    while !host.nil?
      p host_params = { 'host' => host.attributes["name"],
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

###############################################################################
###############################################################################


end #end class

