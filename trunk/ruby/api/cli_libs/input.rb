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

require 'rawline'

class Input_Super

  def get_line
    #place holder
  end
end

class Rawline_Input < Input_Super
  include RawLine

  def initialize
    @editor=Editor.new
    @editor.bind(:ctrl_z) {@editor.undo}
    @editor.basic_word_break_characters = ""

    @editor.completion_proc = lambda do |word|
      p word
    end
    
  end

  def history
    @editor.history
  end

  def set_prompt_func(prompt_func)
    @promptfunc=prompt_func
  end

  def get_line
    line = @editor.read(@promptfunc.call, true)
    return nil if line.nil?
    if line =~ /^\s*$/ or @editor.history.to_a[-2] == line
      @editor.history.back()
    end
    return line
  end

end

class STDIN_Input < Input_Super
  def get_line
    gets
  end
end
