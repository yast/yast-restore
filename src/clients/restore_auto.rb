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
# File:       clients/restore_auto.ycp
# Package:    Restore module
# Summary:    Client for autoinstallation
# Authors:    Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
# This is a client for autoinstallation.
# Does not do any changes to the configuration.
#
module Yast
  class RestoreAutoClient < Client
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      textdomain "restore"

      Yast.import "Popup"
      Yast.import "Restore"
      Yast.import "Wizard"
      Yast.import "Directory"
      Yast.import "FileUtils"

      Yast.include self, "restore/ui.rb"

      # The main ()
      Builtins.y2milestone("-------------------------------")
      Builtins.y2milestone("Restore autoinst client started")

      @ret = nil
      @func = ""
      @param = {}

      @filename = Builtins.sformat(
        "%1/restore_archives_tmpfile.ycp",
        Directory.tmpdir
      )

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))

        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end

      Builtins.y2milestone("func=%1", @func)
      Builtins.y2milestone("param=%1", @param)

      # Import data
      if @func == "Import"
        @ret = Restore.Import(@param)

        if FileUtils.Exists(@filename)
          SCR.Execute(path(".target.remove"), @filename)
        end

        # bugzilla #199657
        SCR.Write(
          path(".target.ycp"),
          @filename,
          Ops.get_list(@param, "archives", [])
        )
      # create a summary
      elsif @func == "Summary"
        @ret = Restore.Summary
      elsif @func == "Reset"
        @ret = Restore.Import({})
      elsif @func == "Change"
        # remember settings which will be overwritten at archive selection
        Restore.Import(@param)
        @ret = RestoreAutoSequence()
      elsif @func == "Packages"
        @ret = {}
      elsif @func == "Export"
        @ret = Restore.Export
      elsif @func == "Write"
        Yast.import "Progress"

        # Read archive file
        @volumes = []

        # bugzilla #199657
        if Ops.get_list(@param, "archives", []) != []
          Builtins.y2milestone("Some volumes set")
          @volumes = Ops.get_list(@param, "archives", [])
        elsif FileUtils.Exists(@filename)
          Builtins.y2milestone("Reading volumes from tmpfile")
          @volumes = Convert.convert(
            SCR.Read(path(".target.ycp"), @filename),
            :from => "any",
            :to   => "list <string>"
          )
        end

        Builtins.y2milestone("Volumes: %1", @volumes)

        if Builtins.size(@volumes) == 0
          @ret = false
          return deep_copy(@ret)
        end

        @read = false
        @ui = :dummy

        @index = 0

        Builtins.foreach(@volumes) do |volume|
          Builtins.y2milestone("Scanning volume %1", volume)
          if @ui == :abort
            @ret = false
            next deep_copy(@ret)
          end
          if @index == 0
            @read = Restore.Read(volume)
          else
            read_result = Restore.ReadNextVolume(volume)
            @read = Ops.get_boolean(read_result, "success", false)
          end
          Builtins.y2milestone("Reading volume %1 returned %2", volume, @read)
          if @read == false
            # read failed, offer manual selection
            input = ""

            # popup dialog text part 1
            if Popup.YesNo(
                (@index == 0 ?
                  _("Archive file cannot be read.") :
                  # popup dialog text part 1
                  _("Archive volume cannot be read.")) +
                  # popup dialog text part 2
                  _("\nSelect it manually?\n")
              ) == true
              if @index == 0
                input = Ops.get(@volumes, @index, "")
              else
                # in selection dialog is proposed new file name, use previous one
                input = Ops.get(@volumes, Ops.subtract(@index, 1), "")
              end

              # select file
              Wizard.CreateDialog # TODO remove this ?
              Wizard.SetDesktopIcon("restore")
              @ui = ArchiveSelectionDialog(@index != 0, false, input) # false = ask only for one file, others are in 'volumes'

              # ask for more volumes if they are not specified
              if @index == 0 && Restore.IsMultiVolume == true &&
                  Builtins.size(@volumes) == 1
                @ui = ArchiveSelectionDialog(true, false, input)
              end

              UI.CloseDialog # TODO remove this ?
            else
              @ret = false
              next deep_copy(@ret)
            end
          end
          @index = Ops.add(@index, 1)
        end

        # set selection
        @selection = Ops.get_map(@param, "selection", {})

        Builtins.foreach(@selection) do |package, info|
          Restore.SetRestoreSelection(package, info)
        end 


        Progress.off
        @blck = lambda { false }

        @write_ret = Restore.Write(@blck, nil, Restore.targetDirectory)
        Progress.on

        Restore.Umount

        @ret = Builtins.size(Ops.get_list(@write_ret, "failed", [])) == 0
        return deep_copy(@ret)
      elsif @func == "GetModified"
        @ret = Restore.Modified
      elsif @func == "SetModified"
        Restore.SetModified
      else
        Builtins.y2error("unknown function: %1", @func)
        @ret = false
      end

      # umount any mounted filesystem
      Restore.Umount

      # Finish
      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("Restore autoinit client finished")
      Builtins.y2milestone("--------------------------------")

      deep_copy(@ret) 
      # EOF
    end
  end
end

Yast::RestoreAutoClient.new.main
