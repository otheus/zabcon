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

require 'rubygems'
require 'treetop'
require 'cli_libs/debug'

class CLIParseError < RuntimeError
end

class ZabconParser

  include ZDebug

  def initialize
    Treetop.load 'cli_libs/parsing_grammar.tt'
    @parser=ZbxAPI_TTParser.new
  end

  def strip_comments(line)
    line.lstrip!
    line.chomp!
    if line =~ /^#.*/ then
      line = ""
    elsif line =~ /(.+)#.*/ then
      line = Regexp.last_match(1)
    else
      line
    end
  end

  def params_to_array(line)
    line.split(' ')
  end

  # converts item to the appropriate data type if need be
  # otherwise it returns item
  def convert_or_parse(item)
    if item.to_i.to_s==item
      return item.to_i
    elsif item =~ /^\[(.*?)\]$/
      array_s=Regexp.last_match(1)
      array=safe_split(array_s,',')
      results=array.collect do |i|
        i.lstrip!
        i.rstrip!
        convert_or_parse(i)
      end
      return results
    else
      return item
    end
  end

  #splits a line at boundaries defined by boundary.
  def safe_split(line,boundary=nil)
    items=[]
    item=""
    quoted=false
    qchar=''
    splitchar= boundary.nil? ? /\s/ : /#{boundary}/

    line.split("").each do |char|  # split up incomming line and account for item="stuff n stuff"
      if !(char=~splitchar) or quoted then  # add the space if we're in a quoted string
        if !quoted  # This block will group text found inside "", () or []
          if char=='"'
            qchar='"'
            quoted=true
#          elsif char=='('
#            qchar=')'
#            quoted=true
          elsif char=='['
            qchar=']'
            quoted=true
          end
        else   #quoted == false
          if char==qchar
            quoted=false
          end
        end
        item<<char
      else
        items<<item if item.length>0
        item=""
      end
    end
    items<<item if item.length>0  # be sure not to forget the last element from the block

    raise CLIParseError, "Closing #{qchar} not found!"  if quoted

    items
  end

  def params_to_hash(line)
    params=safe_split(line)
    debug(6,params)

    retval = {}
    params.each do |item|
      debug(9,item,"parsing")
      item.lstrip!
      item.chomp!
      if item =~ /(.*?)=("(.+)"|([^"]+))/ then
        lside=Regexp.last_match(1)
        rside=convert_or_parse(Regexp.last_match(2))
        retval.merge!(lside=>rside)
      elsif item =~ /(.*?)=""/ then
        lside=Regexp.last_match(1)
        rside=""
        retval.merge!(lside=>rside)
      else
        retval.merge!(item=>true)
      end
      debug(9,retval,"parsed")
    end
    retval
  end

  #parse_input (input:string)
  #parses the input from the user
  #returns a list (command, parameters)
  #parameters is a hash, command is a string
  #possible return values for command.
  # ""                 Unable to parse command
  # non-empty string   Command to execute
  #                    "quit" will be returned if user wants to quit
  def parse_input(input)
    command=""
    params={}

    if input.nil? then
      puts "nil input received"
      return ""
    end

    input=strip_comments(input)

    return "" if input==""

    debug(7,input)

    result=@parser.parse(input)
    if result.nil? then
      puts "Unknown command or syntax error"
      return nil   # we must return true as we don't want to quit.
    end

    rhash=result.pieces()

    cmd=rhash[:command]

    parameters=nil
    if !(params=rhash[:parameters]).nil? then
      case cmd
        when :login
          tmp=params_to_array(params)
          raise "Incorrect number of variables for login" if tmp.length != 3
          parameters={:server=>tmp[0],:username=>tmp[1],:password=>tmp[2]}
        when :loadconfig
          #parameters={:filename=>params_to_array(params)[0]}
          # Quick and dirty fix (parser.parse fails to parse the filename correctly)
          # I would have fixed it, but I couldn't find where parser comes from (@parser=ZbxAPI_TTParser.new)
          parameters={:filename=>input.split[2]}
        when :import
          parameters={:filename=>params_to_array(params)[0]}
        else
          parameters=params_to_hash(params)
      end
    end


    retval={:command=>cmd}
    retval.merge!(:parameters=>parameters) if !parameters.nil?
    retval.merge!(:variable=>rhash[:variable]) if !rhash[:variable].nil?
    retval
  end #end parse_input
end

if __FILE__ == $0

end
