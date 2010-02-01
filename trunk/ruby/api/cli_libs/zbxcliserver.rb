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
# $Id$
# $Revision$
##########################################

require 'zabbixapi'
require 'cli_libs/debug'

class ZbxCliServer

  include ZDebug

  attr_reader :server_url, :user, :password

  def initialize(server,user,password,debuglevel=0)
    @server_url=server
    @user=user
    @password=password
    @debuglevel=debuglevel
    # *Note* Do not rescue errors here, rescue in function that calls this block
    @server=ZbxAPI.new(@server_url,@debuglevel)
    @server.login(@user, @password)
  end

  def debuglevel=(level)
    @server.debug_level=level
  end

  def login?
    !@server.nil?
  end

  def version
    @server.API_version
  end

  def reconnect
    @server.login(@username,@password)
  end

  def checkparams(parameters=nil)
    debug(6,parameters,"Starting - params")
    if parameters.nil? then
      debug(2,"parameters are nil adding show and limit")
      parameters={"limit"=>100, "extendedoutput"=>true}
    else
      if parameters["limit"].nil?
        parameters["limit"]=100
        debug(2,"parameters \"limit\" not found, adding and setting to 100")
      end

      if parameters["show"].nil?
        parameters["extendoutput"]=true
        debug(2,"parameter \"show\" not found, adding")
      end
    end
    debug(6,parameters,"Exiting")
    return parameters
  end

  def getuser(parameters=nil)
    debug(5,parameters,"Starting - params")
    parameters=checkparams(parameters)

    result=@server.user.get(parameters)
    {:class=>:user, :result=>result}
  end

  def gethost(parameters=nil)
    debug(5)
    parameters=checkparams(parameters)

    result=@server.host.get(parameters)
    {:class=>:host, :result=>result}
  end

  def addhost(parameters=nil)
#    Full list of parameters returned buy host.get
#    valid_parameters=[ 'snmp_errors_from', 'ipmi_port', 'outbytes', 'status', 'maintenance_status',
#                       'ipmi_password', 'error', 'ipmi_errors_from', 'available', 'maintenanceid',
#                       'ipmi_privilege', 'useipmi', 'useip', 'maintenance_from', 'ipmi_disable_until',
#                       'port', 'ipmi_available', 'ipmi_ip', 'ipmi_username', 'disable_until', 'ip',
#                       'snmp_available', 'ipmi_authtype', 'lastaccess', 'errors_from', 'host' 'dns',
#                       'proxy_hostid', 'maintenance_type', 'snmp_disable_until', 'inbytes' ]
    valid_parameters=[ 'host', 'port', 'ip', 'dns', 'status', 'port', 'proxy_hostid', 'groupids' ]
    debug(6,parameters,"Parameters passed in")

    if parameters.nil? then
      puts "Add Host requires arguments, valid fields are:"
      puts "host, port, ip or dns, status, port, proxy_hostid"
      puts "example:  add host host=servername dns=host.domain"
      return false
    else
      p_keys = parameters.keys
      valid_parameters.each {|key| p_keys.delete(key)}
      if !p_keys.empty? then
        puts "Invalid items"
        p p_keys
        return false
      elsif !(parameters["dns"].nil? or parameters["ip"].nil?)
        puts "Parameter dns or ip, only one is requireed, not both"
        return false
      elsif (parameters["dns"].nil? and parameters["ip"].nil?)
        puts "Either ip or dns required"
      elsif (parameters["host"].nil?)
        puts "Missing required parameter."
        puts "Required parameters: host"
      else
        parameters["useip"]= parameters["dns"].nil? ? 1 : 0    # dns.nil?=true useip=1, false useip=0
        host=@server.host.create([parameters])
      end
    end
  end

  def getitem(parameters=nil)
    debug(5)
    parameters=checkparams(parameters)

    result=@server.item.get(parameters)
    {:class=>:item, :result=>result}
  end

  def additem(parameters=nil)
    debug(5)
    if !parameters.nil?
      begin
        result=@server.item.add(parameters).values #work around for bug in API
      rescue NoMethodError  # work around a bug from a workaround... YEAH!
        result=[]
      end
    else
      puts "No parameters provided."
    end
  end

  def adduser(parameters=nil)
    debug(5)
    valid_parameters=['name', 'surname', 'alias', 'passwd', 'url', 'autologin',
                      'autologout', 'lang', 'theme', 'refresh', 'rows_per_page', 'type']
    if parameters.nil? then
      puts "Add User requires arguments, valid fields are:"
      puts "name, surname, alias, passwd, url, autologin, autologout, lang, theme, refresh"
      puts "rows_per_page, type"
      puts "example:  add user name=someone alias=username passwd=pass autologout=0"
      return false
    else
      p_keys = parameters.keys
      valid_parameters.each {|key| p_keys.delete(key)}
      if !p_keys.empty? then
        puts "Invalid items"
        p p_keys
        return false
      end
      begin
        uid=@server.user.create(parameters)
        p uid
      rescue ZbxAPI_ParameterError => e
        puts "Add user failed, error: #{e.message}"
      end
    end
  end

  def deleteuser(parameters=nil)
    debug(5)
    if parameters.nil? then
      puts "User id required"
      return
    end
    @server.user.delete(parameters.keys[0].to_i)
  end

  def updateuser(parameters=nil)
    debug(6,parameters)
    valid_parameters=['userid','name', 'surname', 'alias', 'passwd', 'url', 'autologin',
                      'autologout', 'lang', 'theme', 'refresh', 'rows_per_page', 'type',]
    if parameters.nil? or parameters["userid"].nil? then
      puts "Edit User requires arguments, valid fields are:"
      puts "name, surname, alias, passwd, url, autologin, autologout, lang, theme, refresh"
      puts "rows_per_page, type"
      puts "userid is a required field"
      puts "example:  edit user userid=<id> name=someone alias=username passwd=pass autologout=0"
      return false
    else
      p_keys = parameters.keys

      valid_parameters.each {|key| p_keys.delete(key)}
      if !p_keys.empty? then
        puts "Invalid items"
        p p_keys
        return false
      elsif parameters["userid"].nil?
        puts "Missing required userid statement."
      end
      p @server.user.update([parameters])
    end
  end

  def addusermedia(parameters=nil)
    debug(5)
    valid_parameters=["userid", "mediatypeid", "sendto", "severity", "active", "period"]

    if parameters.nil? then
      puts "add usermedia requires arguments, valid fields are:"
      puts "userid, mediatypeid, sendto, severity, active, period"
      puts "example:  add usermedia userid=<id> mediatypeid=1 sendto=myemail@address.com severity=63 active=1 period=\"\""
    else

      p_keys = parameters.keys

      valid_parameters.each {|key| p_keys.delete(key)}
      if !p_keys.empty? then
        puts "Invalid items"
        p p_keys
        return false
      elsif parameters["userid"].nil?
        puts "Missing required userid statement."
      end
      begin
        @server.user.addmedia(parameters)
      rescue ZbxAPI_ParameterError => e
        puts e.message
      end
    end

  end

  def addhostgroup(parameters=nil)
    debug(6,parameters)
    result = @server.hostgroup.create(parameters)
    {:class=>:hostgroup, :result=>result}
  end

  def gethostgroup(parameters=nil)
    debug(5)
    parameters=checkparams(parameters)

    result=@server.hostgroup.get(parameters)
    {:class=>:hostgroup, :result=>result}
  end

  def gethostgroupid(parameters=nil)
    debug(6,parameters)
    result = @server.hostgroup.getId(parameters)
    {:class=>:hostgroup, :result=>result}
  end

  def getapp(parameters=nil)
    debug(5)
    parameters=checkparams(parameters)

    result=@server.application.get(parameters)
    {:class=>:application, :result=>result}
  end

  def addapp(parameters=nil)
    debug(6,parameters)
    result=@server.application.create(parameters)
    {:class=>:application, :result=>result}
  end

  def getappid(parameters=nil)
    debug(6,parameters)
    result=@server.application.getid(parameters)
    {:class=>:application, :result=>result}
  end

  def gettrigger(parameters=nil)
    debug(6,parameters)
    result=@server.trigger.get(parameters)
    {:class=>:trigger, :result=>result}
  end

  # addtrigger( { trigger1, trigger2, triggern } )
  # Only expression and description are mandatory.
  # { { expression, description, type, priority, status, comments, url }, { ...} }
  def addtrigger(parameters=nil)
    debug(6,parameters)
    result=@server.trigger.create(parameters)
    {:class=>:trigger, :result=>result}
  end

  def addlink(parameters=nil)
    debug(6,parameters)
    result=@server.sysmap.addlink(parameters)
    {:class=>:map, :result=>result}
  end

  def addsysmap(parameters=nil)
    debug(6,parameters)
    result=@server.sysmap.create(parameters)
    {:class=>:map, :result=>result}
  end

  def addelementtosysmap(parameters=nil)
    debug(6,parameters)
    result=@server.sysmap.addelement(parameters)
    {:class=>:map, :result=>result}
  end

  def getseid(parameters=nil)
    debug(6,parameters)
    result=@server.sysmap.getseid(parameters)
    {:class=>:map, :result=>result}
  end

  def addlinktrigger(parameters=nil)
    debug(6,parameters)
    result=@server.sysmap.addlinktrigger(parameters)
    {:class=>:map, :result=>result}
  end

end

##############################################
# Unit test
##############################################

if __FILE__ == $0
  zbxcliserver = ZbxCliServer.new("http://localhost/","apitest","test")   #Change as appropriate for platform

  p zbxcliserver.getuser()
end
