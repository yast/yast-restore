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
# File:       clients/restore_bootloader.ycp
# Package:    Restore module
# Summary:    Special client for restoring bootloader settings
# Authors:    Ladislav Slezak <lslezak@suse.cz>
#             Lukas Ocilka <locilka@suse.cz>
#
# $Id$
#
# All bootloader calls were moved here to break building dependency
# on yast2-bootloader
module Yast
  class RestoreBootloaderClient < Client
    def main
      Yast.import "Bootloader"

      @ret = nil

      @ret = Bootloader.Read

      if @ret == false
        Builtins.y2error("Boot loader read failed")
      else
        # write configuration - force re-installation of boot loader
        Bootloader.SetWriteMode({ "save_all" => true })
        @ret = Bootloader.Write

        Builtins.y2error("Boot loader write failed") if @ret == false
      end

      @ret
    end
  end
end

Yast::RestoreBootloaderClient.new.main
