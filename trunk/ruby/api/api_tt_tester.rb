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

require 'rubygems'
require 'treetop'

Treetop.load 'zbx_api.tt'

$parser = ZbxAPI_TTParser.new

def tester(str, testarray, show_result=0, show_obj=0)
  puts "Testing '"+str+"'"
  result=$parser.parse(str)
  p result if show_obj!=0
  if !result.nil? then
    pieces=result.pieces()
    p pieces if show_result!=0
  end

    if ( !result.nil? and !testarray.nil? ) then
    tmp=testarray.clone()
    testarray.each { |key|
      if !pieces[key].nil? then
        pieces.delete(key)
        tmp.delete(key)
      end
    }

    if !pieces.empty? then
      puts "-- TEST FAIL -- - Extra items in result hash"
      p pieces
    elsif !tmp.empty? then
      puts "-- TEST FAIL -- - Test items not found"
      p tmp
    else
      puts "  PASSED"
    end
  elsif result.nil?
    if !testarray.nil? then
      if testarray.empty? then
        puts "  PASSED"
      else
        puts "-- TEST FAIL -- - Test items not found"
        p testarray
      end
    end
  end
end

tester("help",["command"])

tester("get host",["verb","noun"])

tester("$var = get user",["verb","noun","variable"])

tester("get user testval=2",["verb","noun","parameters"],1)

tester("get user testval=2 anothertest=2",["verb","noun","parameter"],1)

tester("get item testval=2",["verb","noun","parameters"],1)

tester("bad command",[])

tester("helpme",[])

tester("help me",[])

tester("# comment",["comment"])

tester("login http://localhost/server nelsonab pass",["command","parameters"],1)

tester("set debug 11",[],1)

tester("set debug 1",["command","parameters"], 1)

tester("set debug 10",["command","parameters"],1)

tester("load configuration",["command"],1)

tester("load configuration file",["command","parameters"],1)

tester("load configuration file.bla.bla",["command","parameters"],1)

tester("save configuration file file2",["command","parameters"],1)

tester("save config file.bla", nil, 1)
