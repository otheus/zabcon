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

module ZDebug

  def set_debug_level(level)   # sets the current debug level for printing messages
    @@debug_level=level
  end

  def debug_level
    @@debug_level
  end

  # level - level to show message (Integer)
  # variable - variable to show (Object)
  # message - message to be prepended before variable  (String)
  def debug(level,variable="",message=nil,truncate=nil)
    raise "Call set_debug before using debug" if !defined?(@@debug_level)
    if level<=@@debug_level
      #parse the caller array to determine who called us, what line, and what file
      caller[0]=~/\/(.*):(\d+):.*`(.*?)'/
      debug_file=$1
      debug_line=$2
      debug_func=$3
      strval=""
      if variable.nil?
        strval="nil"
      elsif variable.class==String
        strval=variable
      else
        strval=variable.inspect
        if !truncate.nil?
          if truncate<strval.length then
            strval=strval[0..truncate]
            strval+= " ..."
          end
        end
      end

      if !message.nil?
        strval = message + ": " + strval
      end
      puts "** #{level} #{debug_file}:#{debug_func}:#{debug_line} #{strval}"
    end
  end

end  # end Debug module
