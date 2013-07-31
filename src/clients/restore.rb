# encoding: utf-8

# ***************************************************************************
#
# Copyright (c) 2000 - 2012 Novell, Inc.
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.   See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail,
# you may find current contact information at www.novell.com
#
# ***************************************************************************
# File:
#   clients/restore.ycp
#
# Package:
#   Restore module
#
# Summary:
#   Main file
#
# Authors:
#   Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
# Main file for restore configuration. Uses all other files.
#
module Yast
  class RestoreClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      #**
      # <h3>Configuration of the restore</h3>

      textdomain "restore"
      Yast.import "Restore"
      Yast.import "CommandLine"

      Yast.include self, "restore/ui.rb"

      @cmdline_description = { "id" => "restore" }

      # The main ()
      Builtins.y2milestone("Restore client started")
      Builtins.y2milestone("----------------------------------------")

      # Command Line Interface support
      @args = WFM.Args
      if Ops.greater_than(Builtins.size(@args), 0)
        @ret2 = CommandLine.Run(@cmdline_description)
        return deep_copy(@ret2)
      end

      # main ui function
      @ret = RestoreSequence()
      Builtins.y2debug("ret == %1", @ret)

      # Finish
      Builtins.y2milestone("Restore client finished")

      # unmount any mounted filesystem
      Restore.Umount

      @ret
    end
  end
end

Yast::RestoreClient.new.main
