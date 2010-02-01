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

require 'cli_libs/debug'

class Parser

  include ZDebug

  attr_reader :commands

  def initialize
    @commands=CommandTree.new("",nil,0)
  end

  def strip_comments(str)
    str.lstrip!
    str.chomp!
    if str =~ /^#.*/ then
      str = ""
    elsif str =~ /(.+)#.*/ then
      str = Regexp.last_match(1)
    else
      str
    end
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



  # Returns nil if the command is incomplete or unknown
  # Returns a hash with :proc and :args for the procedure associated with the matched command and the
  # remaining arguments to the command.  :args is an array of arguments.
  def parse(str)
    debug(7,str,"Parsing")

    str=strip_comments(str)

    nodes = [""]+str.split

    cmd_node=@commands.search(nodes)  # a side effect of the function is that it also manipulates nodes
#    @commands
#    i=0
#    while i<nodes.length
#      tmp=cmd_node.search(nodes[i])
#      break if tmp.nil?
#      cmd_node=tmp
#      i+=1
#    end
#    p
#
#    args=nodes[cmd_node.depth..nodes.length].join(" ")  #the remaining nodes are the arguments
    args=nodes.join(" ")

    args=params_to_hash(args)
    
    if cmd_node.commandproc.nil? then
      puts "\"#{str}\" is an incomplete or unknown command"
      return nil
    else
#      puts "command for \"#{nodes[0..(i-1)].join(" ")}\" is #{cmd_node.commandproc}"
  #      puts "arguments are: \"#{nodes[i..nodes.length].join(" ")}\""
      return {:proc=>cmd_node.commandproc,:args=>args,:helpproc=>cmd_node.helpproc}
    end
  end

  def complete(str,loggedin=false)
    nodes = str.split
    cmd_node=@commands
    i=0
    while i<nodes.length
      tmp=cmd_node.search(nodes[i])
      break if tmp.nil?
      cmd_node=tmp
      i+=1
    end

    if cmd_node.commandproc.nil? then
      # roll up the list of available commands.
      commands = cmd_node.children.collect {|node| node.command}

      # don't include the current node if the command is empty
      if cmd_node.command!="" then commands += [cmd_node.command] end
      return commands
    else
      puts "complete"
      return nil
    end
  end

  def insert(insert_path,command,commandproc,arguments={},helpproc=nil)
    debug(10,{"insert_path"=>insert_path, "command"=>command, "commandproc"=>commandproc, "arguments"=> arguments, "helpproc"=>helpproc})
   insert_path_arr=[""]+insert_path.split   # we must pre-load our array with a blank node at the front
#    p insert_path_arr
    @commands.insert(insert_path_arr,command,commandproc,arguments,helpproc)
  end

end


class CommandTree

  include ZDebug

  attr_reader :command, :commandproc, :children, :arguments, :helpproc, :depth

  # Arguments hash takes the form of {"name"=>{:type=>Class, :optional=>true/false}}
  # If type is nil then the argument takes no options
  def initialize(command,commandproc,depth,arguments={},helpprocc=nil)
    @command=command
    @commandproc=commandproc
    @children=[]
    @arguments=arguments
    @helpprocc=helpprocc
    @depth=depth
  end

  # search will search check to see if the parameter command is found in the current node
  # or the immediate children nodes.  It does not search the tree beyond one level.
  # The loggedin argument is used to differentiate searching for commands which require a valid
  # login or not.  If loggedin is false it will return commands which do not require a valid login.
  def search(search_path)
    debug(10,search_path)
    debug(10,self,"self")

    return nil if search_path.nil?
    debug(10)
    return nil if search_path.empty?
    debug(10)

    retval=nil

    retval=self if search_path[0]==@command


    search_path.shift
    
    return retval if search_path.length==0
    debug(10)

#    p search_path
#    p @children.map {|child| child.command}
    results=@children.map {|child| child.command==search_path[0] ? child : nil }
    results.compact!
    debug(11,results)
    return retval if results.empty?  # no more children to search, return retval which may be self or nil, see logic above
    debug(10)

    return results[0].search(search_path)
    debug(10)
    
    return self if search_path[0]==@command

  end

  # Insert path is the path to insert the item into the tree
  # Insert path is passed in as an array of names which associate with pre-existing nodes
  # The function will recursively insert the command and will remove the top of the input path stack at each level until it
  # finds the appropraite level.  If the appropriate level is never found an exception is raised.
  def insert(insert_path,command,commandproc,arguments={},helpproc=nil,depth=0)
    debug(11,{"insert_path"=>insert_path, "command"=>command, "commandproc"=>commandproc, "arguments"=> arguments,
              "helpproc"=>helpproc, "depth"=>depth})
    debug(11,@command,"self.command")
    debug(11,@children.map {|child| child.command},"children")

    if insert_path[0]==@command then
      debug(11,"Found node")
      if insert_path.length==1 then
        debug(11,command,"inserting")
        @children << CommandTree.new(command,commandproc,depth+1,arguments,helpproc)
      else
        debug(11,"Not found walking tree")
        insert_path.shift
        if !@children.empty? then
          @children.each { |node| node.insert(insert_path,command,commandproc,arguments,helpproc,depth+1)}
        else
          raise Command_Tree_Exception "Unable to find insert point in Command Tree"
        end
      end
    end
  end

end


if __FILE__ == $0

  require 'pp'

  @commands=Parser.new()
  @commands.set_debug_level(6)


  def test_parse(cmd)
    puts "\ntesting \"#{cmd}\""
    retval=@commands.parse(cmd)
    puts "result:"
    p retval
    return retval
  end
  @commands.set_debug_level(0)
  @commands.insert "", "help", lambda { puts "This  is a generic help stub" }
  puts
  @commands.insert "", "get", nil
  puts
  @commands.insert "get", "host", :gethost, {"show"=>{:type=>nil,:optional=>true}}
  @commands.set_debug_level(0)
  puts
  @commands.insert "get", "user", :getuser
  puts
  @commands.insert "get user", "group", :getusergroup
  puts

  pp @commands

  @commands.set_debug_level(0)

  test_parse("get user")
  test_parse("get user show=all arg1 arg2")
  test_parse("get user show=\"id, one, two, three\" arg1 arg2")
  test_parse("get user group show=all arg1")
  test_parse("set value")
  test_parse("help")[:proc].call


  p @commands.complete("hel")
  p @commands.complete("help")
  p @commands.complete("get user all")

end
