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
#   include/restore/ui.ycp
#
# Package:
#   Restore module
#
# Summary:
#   User interface functions.
#
# Authors:
#   Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
# All user interface functions.
#
module Yast
  module RestoreUiInclude
    def initialize_restore_ui(include_target)
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "restore"

      Yast.import "Wizard"
      Yast.import "Progress"
      Yast.import "Restore"
      Yast.import "Mode"
      Yast.import "URL"

      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "Label"
      Yast.import "Package"
      Yast.import "PackageSystem"
      Yast.import "Sequencer"

      Yast.include include_target, "restore/helps.rb"
      Yast.include include_target, "restore/summary_dialog.rb"
      Yast.import "NetworkPopup"

      @restorepackagename = nil

      @archivecontentscache = nil

      @restoredfiles = []
      @failedfiles = []
      @restoredpackages = 0
      @bloaderstatus = nil
      @susestatus = nil

      @packagestoinstall = {}
      @packagestouninstall = {}
      # mounted directory
      @mountdir = ""

      # map with detected removable devices
      @removabledevices = nil

      # last user input, used for dialog skipping
      @lastret = nil
    end

    # Try to detect all removable devices present in the system
    # @return [Hash] Removable devices info

    def DetectRemovable
      ret = {}

      # detect floppy devices
      devices = Mode.test == false ?
        Convert.convert(
          SCR.Read(path(".probe.floppy")),
          :from => "any",
          :to   => "list <map>"
        ) :
        [
          {
            "bus"            => "Floppy",
            "class_id"       => 262,
            "dev_name"       => "/dev/fd0",
            "notready"       => true,
            "old_unique_key" => "xjDN.oZ89vuho4Y3",
            "resource"       => {
              "size" => [
                { "unit" => "cinch", "x" => 350, "y" => 0 },
                { "unit" => "sectors", "x" => 2880, "y" => 512 }
              ]
            },
            "sub_class_id"   => 3,
            "unique_key"     => "sPPV.oZ89vuho4Y3"
          }
        ]
      num = 0

      Builtins.foreach(devices) do |dev|
        dev_name = Ops.get_string(dev, "dev_name", "")
        device = Ops.get_string(dev, "device", "")
        if device == ""
          if Ops.get_string(dev, "bus", "") == "Floppy"
            # floppy disk drive - combo box item
            device = _("Floppy")
          end
        end
        if dev_name != ""
          ret = Builtins.add(
            ret,
            dev_name,
            { "device" => device, "type" => Ops.add(Ops.add("fd", num), "://") }
          )
        end
        num = Ops.add(num, 1)
      end 


      # detect cdrom devices
      devices = Mode.test == false ?
        Convert.convert(
          SCR.Read(path(".probe.cdrom")),
          :from => "any",
          :to   => "list <map>"
        ) :
        [
          {
            "bus"            => "IDE",
            "cdtype"         => "cdrom",
            "class_id"       => 262,
            "dev_name"       => "/dev/hdc",
            "device"         => "CD-540E",
            "driver"         => "ide-cdrom",
            "notready"       => true,
            "old_unique_key" => "3JYE.3LYJ0fijWD1",
            "resource"       => {
              "size" => [{ "unit" => "sectors", "x" => 0, "y" => 512 }]
            },
            "rev"            => "1.0A",
            "sub_class_id"   => 2,
            "unique_key"     => "hY5p.ZxKxy3YdB66"
          }
        ]
      num = 0

      Builtins.foreach(devices) do |dev|
        dev_name = Ops.get_string(dev, "dev_name", "")
        device = Ops.get_string(dev, "device", "")
        if dev_name != ""
          ret = Builtins.add(
            ret,
            dev_name,
            { "device" => device, "type" => Ops.add(Ops.add("cd", num), "://") }
          )
        end
        num = Ops.add(num, 1)
      end 


      deep_copy(ret)
    end

    # Propose next file name of volume from file name
    # @param [String] volume Previuos volume name
    # @return [String] Proposed next volume name

    def ProposeNextVolume(volume)
      # increase number in file name
      pos = Builtins.findlastof(volume, "/")
      volumedir = pos != nil ?
        Builtins.substring(volume, 0, Ops.add(pos, 1)) :
        ""
      volumefile = pos != nil ?
        Builtins.substring(volume, Ops.add(pos, 1)) :
        volume

      # ignore leading zeroes, 0xxx means octal number in tointeger() builtin
      volumenum = Builtins.tointeger(
        Builtins.regexpsub(volumefile, "0*([0-9]+)([^0-9]*)", "\\1")
      )

      volumebase = Builtins.regexpsub(volumefile, "([0-9]+)([^0-9]*)", "\\2")
      newvolume = ""

      if volumenum != nil
        volumenum = Ops.add(volumenum, 1)
        newvolume = Builtins.sformat("%1", volumenum)

        newvolume = Ops.add("0", newvolume) if Builtins.size(newvolume) == 1

        return Ops.add(Ops.add(volumedir, newvolume), volumebase)
      else
        return ""
      end
    end

    # Create list of removable devices for combo box widget.
    # @param [Hash{String => map}] dev Map with devices
    # @param [String] sel Preselected device
    # @return [Array] Combo box content

    def CreateDeviceList(dev, sel)
      dev = deep_copy(dev)
      ret = []

      # add selected device list if it's missing in map
      if sel != nil && sel != "" && !Builtins.haskey(dev, sel)
        ret = [Item(Id(sel), sel)]
      end

      Builtins.foreach(dev) do |d, info|
        ret = Builtins.add(
          ret,
          Item(
            Id(
              Ops.add(
                Ops.add(Ops.add(Ops.get_string(info, "device", ""), " ("), d),
                ")"
              )
            ),
            Ops.add(
              Ops.add(Ops.add(Ops.get_string(info, "device", ""), " ("), d),
              ")"
            ),
            sel == d
          )
        )
      end 


      deep_copy(ret)
    end

    # Enable/disable widget in file selction dialog according to
    # selected input type
    # @param [Symbol] type Symbol of widget which will be enabled (possible values are `file, `nfs, `removable)

    def ShadowButtons(type)
      UI.ChangeWidget(Id(:filename), :Enabled, type == :file)
      UI.ChangeWidget(Id(:selectfile), :Enabled, type == :file)

      UI.ChangeWidget(Id(:nfsserver), :Enabled, type == :nfs)
      UI.ChangeWidget(Id(:nfsfilename), :Enabled, type == :nfs)
      UI.ChangeWidget(Id(:selecthost), :Enabled, type == :nfs)

      UI.ChangeWidget(Id(:device), :Enabled, type == :removable)
      UI.ChangeWidget(Id(:remfilename), :Enabled, type == :removable)
      UI.ChangeWidget(Id(:remfile), :Enabled, type == :removable)

      nil
    end


    # Convert selected device name in combobox to URL-like equivalent
    # @param [String] selected Selected string in combo box
    # @param [Hash{String => map}] dev Devices info
    # @return [String] Device name in URL-like syntax

    def ComboToDevice(selected, dev)
      dev = deep_copy(dev)
      ret = ""

      Builtins.foreach(dev) do |d, info|
        if selected ==
            Ops.add(
              Ops.add(Ops.add(Ops.get_string(info, "device", ""), " ("), d),
              ")"
            )
          ret = Ops.get_string(info, "type", "cd://")
        end
      end 


      ret = Ops.add(Ops.add("dev://", selected), ":") if ret == ""

      ret
    end

    # Backup archive is selected in this dialog.
    # @param [Boolean] multivolume True = first archive file is entered, otherwise volume parts are entered
    # @param [Boolean] askformore False: ask only for one volume part, true: ask until all volumes are entered
    # @return [Symbol] UI::UserInput() result
    def ArchiveSelectionDialog(multivolume, askformore, input)
      Builtins.y2debug("input: %1", input)

      # cache removable devices
      if @removabledevices == nil
        @removabledevices = DetectRemovable()
        Builtins.y2milestone(
          "Detected removable devices: %1",
          @removabledevices
        )
      end

      if multivolume == false && Mode.config == false
        # clear previous selection
        Restore.ResetArchiveSelection
      end

      file_name = ""
      nfs_server = ""
      nfs_file = ""
      cd_file = ""

      type = :file
      dev = ""

      urlinput = input != nil && input != "" ? input : Restore.inputname
      proposal = ""

      if urlinput != nil
        Builtins.y2debug("urlinput: %1", urlinput)

        parsed_url = URL.Parse(urlinput)
        scheme = Ops.get_string(parsed_url, "scheme", "file")

        if scheme == "nfs"
          type = :nfs
          nfs_server = Ops.get_string(parsed_url, "host", "")
          nfs_file = Ops.get_string(parsed_url, "path", "")
          proposal = nfs_file
        elsif Builtins.regexpmatch(scheme, "^cd[0-9]*") ||
            Builtins.regexpmatch(scheme, "^fd[0-9]*")
          type = :removable

          devindex = Builtins.regexpsub(scheme, "[cf]d0*([0-9]*)", "\\1")

          devindex = "0" if devindex == nil || devindex == ""

          if Mode.test == false
            devpath = Builtins.regexpmatch(scheme, "^cd[0-9]*") ?
              path(".probe.cdrom") :
              path(".probe.floppy")
            devicemaps = Convert.convert(
              SCR.Read(devpath),
              :from => "any",
              :to   => "list <map>"
            )
            devicemap = Ops.get(devicemaps, Builtins.tointeger(devindex), {})
            dev = Ops.get_string(devicemap, "dev_name", "") 
            # dev = lookup(select((list<map>) SCR::Read(devpath), tointeger(devindex), $[]), "dev_name", "");
          end

          cd_file = Ops.get_string(parsed_url, "path", "")
          proposal = cd_file
        elsif scheme == "dev"
          type = :removable
          dev = Ops.add("/dev/", Ops.get_string(parsed_url, "host", ""))
          file_name = Ops.get_string(parsed_url, "path", "")
          proposal = file_name
        else
          type = :file
          file_name = Ops.get_string(parsed_url, "path", "")
          proposal = file_name
        end

        if urlinput == input && multivolume == true
          proposal = ProposeNextVolume(proposal)

          if proposal != ""
            if type == :removable
              cd_file = proposal
            elsif type == :nfs
              nfs_file = proposal
            else
              file_name = proposal
            end
          end
        end
      end

      # unmount previous file system
      Restore.Umount

      contents = VBox(
        # frame label
        Frame(
          multivolume == false ? _("Backup Archive") : _("Multivolume Archive"),
          HBox(
            RadioButtonGroup(
              Id(:source),
              Opt(:notify),
              VBox(
                VSpacing(0.5),
                # radio button label
                Left(
                  RadioButton(
                    Id(:file),
                    Opt(:notify),
                    _("&Local File"),
                    type == :file
                  )
                ),
                VSquash(
                  HBox(
                    HSpacing(2),
                    # text entry label
                    Bottom(
                      TextEntry(
                        Id(:filename),
                        _("Archive Filena&me"),
                        file_name
                      )
                    ),
                    HSpacing(1),
                    # push button label
                    Bottom(PushButton(Id(:selectfile), _("&Select...")))
                  )
                ),
                VSpacing(1),
                # radio button label
                Left(
                  RadioButton(
                    Id(:nfs),
                    Opt(:notify),
                    _("Network (N&FS)"),
                    type == :nfs
                  )
                ),
                VSquash(
                  HBox(
                    HSpacing(2),
                    # text entry label
                    Bottom(
                      TextEntry(
                        Id(:nfsserver),
                        _("I&P Address or Name of NFS Server"),
                        nfs_server
                      )
                    ),
                    HSpacing(1),
                    # push button label
                    Bottom(PushButton(Id(:selecthost), _("Select &Host...")))
                  )
                ),
                HBox(
                  HSpacing(2),
                  # text entry label
                  TextEntry(Id(:nfsfilename), _("&Archive Filename"), nfs_file)
                ),
                VSpacing(1),
                # radio button label
                Left(
                  RadioButton(
                    Id(:removable),
                    Opt(:notify),
                    _("Rem&ovable Device"),
                    type == :removable
                  )
                ),
                HBox(
                  HSpacing(2),
                  # combo box label
                  Left(
                    ComboBox(
                      Id(:device),
                      Opt(:editable),
                      _("&Device"),
                      CreateDeviceList(@removabledevices, dev)
                    )
                  )
                ),
                VSquash(
                  HBox(
                    HSpacing(2),
                    # text entry label
                    Bottom(
                      TextEntry(
                        Id(:remfilename),
                        _("Archi&ve Filename"),
                        cd_file
                      )
                    ),
                    HSpacing(1),
                    # push button label
                    Bottom(PushButton(Id(:remfile), _("S&elect...")))
                  )
                ),
                VSpacing(1)
              )
            ),
            HSpacing(1)
          )
        ),
        VSpacing(1)
      )

      # dialog header
      title = multivolume == false ?
        _("Archive Selection") :
        _("Multivolume Archive Selection")

      Wizard.SetContents(
        title,
        contents,
        multivolume == true ?
          ArchiveMultiSelectionHelp() :
          ArchiveSelectionHelp(),
        true,
        true
      )

      ShadowButtons(type)

      ret = nil
      begin
        ret = UI.UserInput

        if ret == :selectfile
          file = UI.AskForExistingFile("/", "*.tar", _("Select Archive File"))

          if file != nil && file != ""
            UI.ChangeWidget(Id(:filename), :Value, file)
          end
        end
        if ret == :selecthost
          selectedhost = NetworkPopup.NFSServer(
            Convert.to_string(UI.QueryWidget(Id(:nfsserver), :Value))
          )

          if selectedhost != "" && selectedhost != nil
            UI.ChangeWidget(Id(:nfsserver), :Value, selectedhost)
          end
        elsif ret == :nfs || ret == :removable || ret == :file
          ShadowButtons(
            Convert.to_symbol(UI.QueryWidget(Id(:source), :CurrentButton))
          )
        elsif ret == :remfile
          selected = Convert.to_string(UI.QueryWidget(Id(:device), :Value))
          device = ComboToDevice(selected, @removabledevices)
          fname = Convert.to_string(UI.QueryWidget(Id(:remfilename), :Value))

          # file selection from removable device - mount device
          mount = Restore.MountInput(Ops.add(device, fname))

          if Ops.get_boolean(mount, "success", false) == true
            mountpnt = Ops.get_string(mount, "mpoint", "/")
            file = UI.AskForExistingFile(
              Ops.add(mountpnt, "/"),
              "*.tar",
              _("Select Archive File")
            )

            if file != nil && file != ""
              # check if file is under mountpoint directory
              if Builtins.substring(file, 0, Builtins.size(mountpnt)) != mountpnt
                # error message - selected file is out of mounted file system
                Popup.Error(
                  _("The selected file is not on the mounted device.")
                )
              else
                # set file name
                UI.ChangeWidget(
                  Id(:remfilename),
                  :Value,
                  Builtins.substring(file, Builtins.size(mountpnt))
                )
              end
            end

            # umount file system
            SCR.Execute(path(".target.umount"), mountpnt)
          else
            # error message
            Popup.Error(_("Cannot mount file system."))
          end
        elsif ret == :next
          type2 = Convert.to_symbol(UI.QueryWidget(Id(:source), :CurrentButton))

          if Mode.test == true
            input = "file:///tmp/archive.tar"
          elsif type2 == :file
            fname = Convert.to_string(UI.QueryWidget(Id(:filename), :Value))

            if fname == ""
              # error message - file name is missing
              Popup.Error(_("Enter a valid filename."))
              input = ""
            else
              input = Ops.add("file://", fname)
            end
          elsif type2 == :nfs
            server = Convert.to_string(UI.QueryWidget(Id(:nfsserver), :Value))
            file = Convert.to_string(UI.QueryWidget(Id(:nfsfilename), :Value))

            if server == "" || file == ""
              # error message - file or server name is missing
              Popup.Error(_("Enter a valid server and filename."))
              input = ""
            else
              input = Ops.add(Ops.add(Ops.add("nfs://", server), ":"), file)
            end
          elsif type2 == :removable
            selected = Convert.to_string(UI.QueryWidget(Id(:device), :Value))
            device = ComboToDevice(selected, @removabledevices)
            fname = Convert.to_string(UI.QueryWidget(Id(:remfilename), :Value))

            Builtins.y2milestone("Selected removable device: %1", device)

            if device == "" || fname == ""
              # error message - file or device name is missing
              Popup.Error(_("Enter a valid device and filename."))
              input = ""
            else
              input = Ops.add(device, fname)
            end
          else
            Builtins.y2error("Unknown source type %1", type2)
          end

          if input != ""
            configure = true

            if Mode.config
              # popup question
              answer = Popup.YesNo(
                _(
                  "Detailed configuration requires reading the archive.\n" +
                    "If an archive is not read, full restoration will be configured.\n" +
                    "\n" +
                    "Read the selected archive?\n"
                )
              )

              configure = answer
              Restore.completerestoration = !answer
              Builtins.y2debug(
                "completerestoration: %1",
                Restore.completerestoration
              )

              if !configure
                Restore.runbootloader = true
                Restore.restoreRPMdb = true
                Restore.inputname = input
              end
            end

            if configure
              readresult = false
              lastvolume = false

              # progress message
              UI.OpenDialog(Label(_("Reading archive contents...")))

              Builtins.y2debug(
                "Restore::IsMultiVolume(): %1",
                Restore.IsMultiVolume
              )

              if Restore.IsMultiVolume == false
                readresult = Restore.Read(input)
              else
                # read next volume
                nextresult = Restore.ReadNextVolume(input)
                readresult = Ops.get_boolean(nextresult, "success", false)
                lastvolume = Ops.get_boolean(nextresult, "lastvolume", false)
              end

              UI.CloseDialog

              if readresult == false
                # error message - %1 is archive file name
                Popup.Error(
                  Builtins.sformat(
                    _("Cannot read backup archive file %1."),
                    input
                  )
                )
                Restore.Umount
                ret = :dummy
              else
                @restoredfiles = []
                @failedfiles = []

                if Restore.IsMultiVolume == true && askformore == true
                  # umount source and ask for next volume
                  Restore.Umount

                  if lastvolume == false
                    if multivolume == true
                      widget = nil

                      if type2 == :file
                        widget = :filename
                      elsif type2 == :removable
                        widget = :remfilename
                      elsif type2 == :nfs
                        widget = :nfsfilename
                      else
                        Builtins.y2warning("Unknown source type: %1", type2)
                      end

                      fn = Convert.to_string(UI.QueryWidget(Id(widget), :Value))
                      prop = ProposeNextVolume(fn)

                      UI.ChangeWidget(Id(widget), :Value, prop) if prop != ""

                      ret = :dummy
                    end
                  else
                    # last volume - test all volumes together
                    testall = Restore.TestAllVolumes

                    Builtins.y2debug("TestAllVolumes(): %1", testall)

                    if testall == false
                      Builtins.y2error("Test Restore::TestAllVolumes() failed")
                      # error message - multi volume archive consistency check failed
                      Popup.Error(
                        _(
                          "Test of all volumes failed.\n" +
                            "\tAn archive file is probably corrupted.\n" +
                            "\t"
                        )
                      )

                      ret = :back
                    end
                  end
                end
              end
            else
              ret = :noconfig
            end
          else
            ret = :dummy
          end
        elsif ret == :cancel
          ret = :abort
        end
      end while ret != :next && ret != :abort && ret != :back && ret != :multi &&
        ret != :noconfig

      Convert.to_symbol(ret)
    end

    # Display archive property - date of backup, user comment...
    # @return [Symbol] UI::UserInput() result
    def ArchivePropertyDialog
      if Mode.config == false
        Builtins.y2milestone(
          "missing packages %1: ",
          Restore.GetMissingPackages
        )
        Builtins.y2milestone("extra packages %1: ", Restore.GetExtraPackages)
        Builtins.y2milestone(
          "mismatched packages %1: ",
          Restore.GetMismatchedPackages
        )
      end

      date = Restore.GetArchiveDate
      hostname = Restore.GetArchiveHostname
      comment = Restore.GetArchiveComment
      archname = Restore.GetInputName

      multivolume = Restore.IsMultiVolume == true ? _("Yes") : _("No")

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          # label text
          Left(
            HBox(
              Label(Id(:flabel), _("Archive Filename:")),
              HSpacing(2),
              Label(Id(:flabel2), archname)
            )
          ),
          VSpacing(0.5),
          # label text
          Left(
            HBox(
              Label(Id(:dlabel), _("Date of Backup:")),
              HSpacing(2),
              Label(Id(:dlabel2), date)
            )
          ),
          VSpacing(0.5),
          # label text
          Left(
            HBox(
              Label(Id(:hlabel), _("Backup Hostname:")),
              HSpacing(2),
              Label(Id(:hlabel2), hostname)
            )
          ),
          VSpacing(0.5),
          # label text
          Left(
            HBox(
              Label(Id(:mlabel), _("Multivolume Archive:")),
              HSpacing(2),
              Label(Id(:mlabel2), multivolume)
            )
          ),
          VSpacing(1.0),
          # multi line widget label
          Left(Label(_("Archive &Description:"))),
          RichText(Id(:description), Opt(:plainMode), comment),
          VSpacing(1.0),
          # push button label
          PushButton(Id(:details), Opt(:key_F2), _("&Archive Content...")),
          VSpacing(1),
          # push button label
          PushButton(Id(:options), Opt(:key_F7), _("E&xpert Options...")),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      # dialog header
      Wizard.SetContents(
        _("Archive Properties"),
        contents,
        ArchivePropertyHelp(),
        true,
        true
      )

      ret = nil
      begin
        ret = UI.UserInput

        ret = :abort if ret == :cancel
      end while ret != :next && ret != :abort && ret != :back && ret != :details &&
        ret != :options

      if Restore.IsMultiVolume == true && Restore.TestAllVolumes == false &&
          ret == :next
        # ask for next volumes
        ret = :multi
      end

      @lastret = Convert.to_symbol(ret)
      Convert.to_symbol(ret)
    end

    # Return content for table widget - list of backup files
    # @param [Hash <String, Hash{String => Object>}] packagesinfo Map $[ "packagename" : $[ "files" : ["files in the archive"] ] ]
    # @return [Array] Table content
    def CreateArchiveContentTree(packagesinfo)
      packagesinfo = deep_copy(packagesinfo)
      ret = []
      num = 0

      Builtins.foreach(packagesinfo) do |p, info|
        files = Ops.get_list(info, "files", [])
        itemfiles = []
        version = Ops.get_string(info, "vers", "")
        itemfiles = Builtins.maplist(files) { |s| Item(s) }
        if p == ""
          # package name for files not owned by any package
          p = _("--No package--")
        end
        ret = Builtins.add(
          ret,
          Item(Id(num), Ops.add(Ops.add(p, "-"), version), itemfiles)
        )
        num = Ops.add(num, 1)
      end if packagesinfo != nil

      deep_copy(ret)
    end

    # Display content of backup archive in the table.
    # @return [Symbol] UI::UserInput() result
    def ArchiveContentsDialog
      Wizard.ClearContents

      if @archivecontentscache == nil
        @archivecontentscache = CreateArchiveContentTree(Restore.GetArchiveInfo)
      end

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          # tree label
          Tree(
            Id(:tree),
            _("Archive &Contents"),
            CreateArchiveContentTree(Restore.GetArchiveInfo)
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      Wizard.SetNextButton(:next, Label.OKButton)

      # dialog header
      Wizard.SetContents(
        _("Archive Contents"),
        contents,
        ArchiveContentHelp(),
        true,
        true
      )

      ret = nil
      begin
        ret = UI.UserInput

        ret = :abort if ret == :cancel
      end while ret != :next && ret != :abort && ret != :back

      Wizard.RestoreNextButton

      Convert.to_symbol(ret)
    end

    # Dialog with options.
    # @return UI::UserInput() result
    def RestoreOptionsDialog
      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          # check box label - restore option
          Left(
            CheckBox(
              Id(:lilo),
              _("Activate &Boot Loader Configuration after Restoration"),
              Restore.runbootloader
            )
          ),
          VSpacing(1),
          # check box label - restore option
          Left(
            TextEntry(
              Id(:target),
              _("Target Directory"),
              Restore.targetDirectory
            )
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      Wizard.SetNextButton(:next, Label.OKButton)

      # dialog header
      Wizard.SetContents(
        _("Restore Options"),
        contents,
        RestoreOptionsHelp(),
        true,
        true
      )

      ret = nil
      target_dir = "/"
      begin
        ret = UI.UserInput

        target_dir = Convert.to_string(UI.QueryWidget(Id(:target), :Value))

        if Builtins.size(target_dir) == 0 ||
            Builtins.substring(target_dir, 0, 1) != "/"
          # error message - entered directory is empty or doesn't start with / character
          Popup.Error(
            _("The target directory is invalid or the path is not absolute.")
          )

          ret = nil
        end
      end while ret != :next && ret != :abort && ret != :back

      if ret == :cancel
        ret = :abort
      else
        Restore.runbootloader = Convert.to_boolean(
          UI.QueryWidget(Id(:lilo), :Value)
        )
        Restore.targetDirectory = Convert.to_string(
          UI.QueryWidget(Id(:target), :Value)
        )
      end

      Wizard.RestoreNextButton

      Convert.to_symbol(ret)
    end

    # Create content for table widget - columns: selection mark, package name, backup version, installed version, description
    # @param [Hash <String, Hash{String => String>}] contents Map $[ "packagename" : $[ "ver" : "version", "descr" : "short description" ] ]
    # @param [Boolean] defaultval if true "X" is in the first column, else " "
    # @param [Hash] selected Selected packages (only for autoinstallation, otherwise should be nil)
    # @return [Array] Contents for Table widget
    def CreateTableContentsWithMismatched(contents, selected, defaultval)
      contents = deep_copy(contents)
      selected = deep_copy(selected)
      ret = []
      num = 0

      defval = defaultval == true ? "X" : " "

      Builtins.foreach(contents) do |p, m|
        ver = Ops.get(m, "ver", "")
        descr = Ops.get(m, "descr", "")
        installed = Ops.get(m, "inst", "")
        defval = Builtins.haskey(selected, p) ? "X" : " " if selected != nil
        ret = Builtins.add(ret, Item(Id(num), defval, p, ver, installed, descr))
        num = Ops.add(num, 1)
      end if contents != nil

      deep_copy(ret)
    end


    # Dialog for package selection - packages to install
    # @return [Symbol] UI::UserInput() result
    def SelectionInstallDialog
      missingpackages = Restore.GetMissingPackages

      # add mismatched packages
      Builtins.foreach(Restore.GetMismatchedPackages) do |p, info|
        missingpackages = Builtins.add(missingpackages, p, info)
      end 


      # if all packages are installed return `next (or `back)
      return @lastret if Builtins.size(missingpackages) == 0

      missing = CreateTableContentsWithMismatched(
        missingpackages,
        @packagestoinstall,
        true
      )
      # table header
      header = Header(
        " ",
        _("Package"),
        _("Version"),
        _("Installed Version"),
        _("Description")
      )

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          Table(Id(:pkg), Opt(:notify), header, missing),
          VSpacing(1),
          HBox(
            # push button label
            PushButton(Id(:all), _("&Select All")),
            # push button label
            PushButton(Id(:none), _("&Deselect All"))
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      # dialog header
      Wizard.SetContents(
        _("Package Restoration: Installation"),
        contents,
        InstallPackageHelp(),
        true,
        true
      )

      ret = nil
      begin
        ret = UI.UserInput

        if ret == :all
          UI.ChangeWidget(
            Id(:pkg),
            :Items,
            CreateTableContentsWithMismatched(missingpackages, nil, true)
          )
        elsif ret == :none
          UI.ChangeWidget(
            Id(:pkg),
            :Items,
            CreateTableContentsWithMismatched(missingpackages, nil, false)
          )
        elsif ret == :pkg
          current = Convert.to_integer(UI.QueryWidget(Id(:pkg), :CurrentItem))
          current_item = Convert.to_term(
            UI.QueryWidget(Id(:pkg), term(:Item, current))
          )
          current_value = Ops.get_string(current_item, 1, " ")
          # string current_value = (string) select((term) UI::QueryWidget(`id(`pkg), `Item(current)), 1, " ");

          if current_value == " "
            current_value = "X"
          else
            current_value = " "
          end

          UI.ChangeWidget(Id(:pkg), term(:Item, current, 0), current_value)
        elsif ret == :cancel
          ret = :abort
        end
      end while ret != :next && ret != :abort && ret != :back

      if ret != :abort
        num = Builtins.size(missingpackages)
        i = 0

        @packagestoinstall = {}

        while Ops.less_than(i, num)
          current_item = Convert.to_term(
            UI.QueryWidget(Id(:pkg), term(:Item, i))
          )
          s = Ops.get_string(current_item, 1, " ")
          p = Ops.get_string(current_item, 2, " ")
          # string s = (string) select((term) UI::QueryWidget(`id(`pkg), `Item(i)), 1, " ");
          # string p = (string) select((term) UI::QueryWidget(`id(`pkg), `Item(i)), 2, " ");

          if s == "X"
            i2 = Ops.get(missingpackages, p, {})
            v = Ops.get_string(i2, "ver", "")
            @packagestoinstall = Builtins.add(
              @packagestoinstall,
              p,
              { "ver" => v }
            )

            # change default restore status to 'restore' for packages which will be installed
            if Builtins.haskey(Restore.GetArchiveInfo, p)
              Restore.SetRestoreSelection(p, { "sel_type" => "X" })
            end
          else
            # change default restore status to 'do not restore' for packages which will not be installed
            if Builtins.haskey(Restore.GetArchiveInfo, p)
              Restore.SetRestoreSelection(p, { "sel_type" => " " })
            end

            if Builtins.haskey(@packagestoinstall, p)
              @packagestoinstall = Builtins.remove(@packagestoinstall, p)
            end
          end

          i = Ops.add(i, 1)
        end

        Builtins.y2milestone(
          "Selected packages to install: %1",
          @packagestoinstall
        )
      end

      # TODO: warn if some packages are not available on CDs and display path selection dialog to packages
      # LATER: allow to select package from backup archive (YOU stores packages to /var/... and they can be used)

      @lastret = Convert.to_symbol(ret)
      Convert.to_symbol(ret)
    end


    # Create content for table widget - columns: selection mark, package name, version, description
    # @param [Hash <String, Hash{String => String>}] contents Map $[ "packagename" : $[ "ver" : "version", "descr" : "short description" ] ]
    # @param [Boolean] defaultval if true "X" is in the first column, else " "
    # @param [Hash] selected Selected packages (only for autoinstallation, otherwise should be nil)
    # @return [Array] Contents for Table widget
    def CreateTableContents(contents, selected, defaultval)
      contents = deep_copy(contents)
      selected = deep_copy(selected)
      ret = []
      num = 0

      defval = defaultval == true ? "X" : " "

      Builtins.foreach(contents) do |p, m|
        ver = Ops.get(m, "ver", "")
        descr = Ops.get(m, "descr", "")
        defval = Builtins.haskey(selected, p) ? "X" : " " if selected != nil
        ret = Builtins.add(ret, Item(Id(num), defval, p, ver, descr))
        num = Ops.add(num, 1)
      end if contents != nil

      deep_copy(ret)
    end


    # Dialog for package selection - packages to uninstall
    # @return [Symbol] UI::UserInput() result
    def SelectionUninstallDialog
      extrapackages = Restore.GetExtraPackages

      # if none extra package is installed return `next (or `back)
      return @lastret if Builtins.size(extrapackages) == 0

      extra = CreateTableContents(extrapackages, @packagestouninstall, true)
      # table header
      header = Header(" ", _("Package"), _("Version"), _("Description"))

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          Table(Id(:pkg), Opt(:notify), header, extra),
          VSpacing(1),
          HBox(
            # push button label
            PushButton(Id(:all), _("&Select All")),
            # push button label
            PushButton(Id(:none), _("&Deselect All"))
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      # dialog header
      Wizard.SetContents(
        _("Package Restoration: Uninstallation"),
        contents,
        UninstallPackageHelp(),
        true,
        true
      )

      ret = nil
      begin
        ret = UI.UserInput

        if ret == :all
          UI.ChangeWidget(
            Id(:pkg),
            :Items,
            CreateTableContents(extrapackages, nil, true)
          )
        elsif ret == :none
          UI.ChangeWidget(
            Id(:pkg),
            :Items,
            CreateTableContents(extrapackages, nil, false)
          )
        elsif ret == :pkg
          current = Convert.to_integer(UI.QueryWidget(Id(:pkg), :CurrentItem))
          current_item = Convert.to_term(
            UI.QueryWidget(Id(:pkg), term(:Item, current))
          )
          current_value = Ops.get_string(current_item, 1, " ")
          # string current_value = (string) select((term) UI::QueryWidget(`id(`pkg), `Item(current)), 1, " ");

          if current_value == " "
            current_value = "X"
          else
            current_value = " "
          end

          UI.ChangeWidget(Id(:pkg), term(:Item, current, 0), current_value)
        elsif ret == :cancel
          ret = :abort
        end
      end while ret != :next && ret != :abort && ret != :back

      if ret != :abort
        num = Builtins.size(extrapackages)
        i = 0

        @packagestouninstall = {}

        while Ops.less_than(i, num)
          current_item = Convert.to_term(
            UI.QueryWidget(Id(:pkg), term(:Item, i))
          )
          s = Ops.get_string(current_item, 1, " ")
          p = Ops.get_string(current_item, 2, " ")
          # string s = (string) select((term) UI::QueryWidget(`id(`pkg), `Item(i)), 1, " ");
          # string p = (string) select((term) UI::QueryWidget(`id(`pkg), `Item(i)), 2, " ");

          if s == "X"
            i2 = Ops.get(extrapackages, p, {})
            v = Ops.get_string(i2, "ver", "")
            @packagestouninstall = Builtins.add(
              @packagestouninstall,
              p,
              { "ver" => v }
            )
          elsif p != nil && Builtins.haskey(@packagestouninstall, p)
            @packagestouninstall = Builtins.remove(@packagestouninstall, p)
          end

          i = Ops.add(i, 1)
        end

        Builtins.y2milestone(
          "Selected packages to uninstall: %1",
          @packagestouninstall
        )
      end

      @lastret = Convert.to_symbol(ret)
      Convert.to_symbol(ret)
    end

    # Start Yast2 package manager
    # @return [Symbol] UI::UserInput() result
    def SWsingleDialog
      install = []
      uninstall = []

      return :back if @lastret == :back

      if Ops.greater_than(Builtins.size(@packagestoinstall), 0)
        Builtins.foreach(@packagestoinstall) do |k, v|
          install = Builtins.add(install, k)
        end
      end

      if Ops.greater_than(Builtins.size(@packagestouninstall), 0)
        Builtins.foreach(@packagestouninstall) do |k, v|
          uninstall = Builtins.add(uninstall, k)
        end
      end

      Builtins.y2milestone("install: %1", install)
      Builtins.y2milestone("uninstall: %1", uninstall)

      unavailable_packages = []

      # Initialize the package manager (the same way it is used later)
      # before checking for packages availability
      PackageSystem.EnsureSourceInit

      # BNC #553400: Checking for all packages to install whether they are available
      Builtins.foreach(install) do |one_package|
        # Package is not available - cannot be installed
        if Pkg.IsAvailable(one_package) != true
          if Popup.AnyQuestion(
              # Headline
              _("Error"),
              # Error message
              Builtins.sformat(
                _(
                  "Package %1 is not available on any of the subscribed repositories.\nWould you like to got back and deselect the package or skip it?\n"
                ),
                one_package
              ),
              _("Yes, Go &Back"),
              _("&Skip"),
              :focus_yes
            )
            Builtins.y2milestone(
              "User has decided to go back an unselect the package (%1)",
              one_package
            )
            @lastret = :back
            raise Break
          else
            unavailable_packages = Builtins.add(
              unavailable_packages,
              one_package
            )
            Builtins.y2warning(
              "User decided to skip missing package (%1)",
              one_package
            )
          end
        end
      end

      # Remove all unavailable packages from list of packages to install
      Builtins.foreach(unavailable_packages) do |do_not_install_package|
        install = Builtins.filter(install) do |one_package|
          one_package != do_not_install_package
        end
      end

      return :back if @lastret == :back

      if Ops.greater_than(Builtins.size(install), 0) ||
          Ops.greater_than(Builtins.size(uninstall), 0)
        if Package.DoInstallAndRemove(install, uninstall) != true
          Report.Error(
            _("Installation or removal of some packages has failed.")
          )
        end

        Restore.ReadActualInstalledPackages
      end

      @lastret
    end

    # Return table widget contens - files and packages selected for restoration
    # @param [Hash <String, Hash{String => Object>}] restoreselection Restore settings
    # @return [Array] Table content
    def CreateTableContentsRestoreSelection(restoreselection)
      restoreselection = deep_copy(restoreselection)
      ret = []
      # id of item in the table
      num = 0

      Builtins.foreach(restoreselection) do |p, m|
        ver = Ops.get_string(m, "vers", "")
        descr = Ops.get_string(m, "descr", "")
        seltype = Ops.get_string(m, "sel_type", " ")
        numfiles = ""
        if seltype == "X"
          # all files selected for restoration
          numfiles = _("All")
        elsif seltype == " "
          numfiles = ""
        elsif seltype == "P"
          total = Builtins.size(Ops.get_list(m, "files", []))
          sel = Builtins.size(Ops.get_list(m, "sel_file", []))

          # selected %1 (number of files) of %2 (number of files)
          numfiles = Builtins.sformat(_("%1 of %2"), sel, total)
        else
          Builtins.y2error("Unknown selection type: %1", seltype)
        end
        if p == ""
          # name for "no package" - files not owned by any package
          p = _("--No package--")
        end
        ret = Builtins.add(ret, Item(Id(num), seltype, numfiles, p, ver, descr))
        num = Ops.add(num, 1)
      end if restoreselection != nil

      deep_copy(ret)
    end

    # Ask wheter missing package should be installed and restored
    # @param [String] package Package name
    # @param [String] version Package version
    # @return [Boolean] True if package should be installed

    def InstallQuestion(package, version)
      ret = false

      if Mode.config == true
        # do not ask in autoinstall config mode
        return true
      end

      if package != "" &&
          !Builtins.haskey(Restore.GetActualInstalledPackages, package) &&
          !Builtins.haskey(@packagestoinstall, package)
        # popup question - %1 is package name
        ret = Popup.AnyQuestion(
          "",
          Builtins.sformat(
            _("Package %1 is not installed in your system.\nInstall it?\n"),
            Ops.add(Ops.add(package, "-"), version)
          ),
          Label.YesButton,
          Label.NoButton,
          :focus_yes
        )

        if ret == true
          # add package to the map of installed packages
          @packagestoinstall = Builtins.add(
            @packagestoinstall,
            package,
            { "ver" => version }
          )
        end
      end

      ret
    end

    # Packages (and files) for restoration can be selected in this archive.
    # @return [Symbol] UI::UserInput() result
    def PackageSelectionRestoreDialog
      button = PushButton(Id(:files), Opt(:key_F7), _("S&elect Files"))

      tablecontents = CreateTableContentsRestoreSelection(
        Restore.GetArchiveInfo
      )
      position = 0

      # refresh previous selection
      Builtins.foreach(tablecontents) do |t|
        # if (restorepackagename == select(t, 3, ""))
        if @restorepackagename == Ops.get_string(t, 3, "")
          position = Ops.get_integer(t, [0, 0], 0)
        end
      end if @restorepackagename != nil

      proposedRPMrestoration = Restore.ProposeRPMdbRestoration
      Builtins.y2milestone(
        "Proposed RPM restoration: %1",
        proposedRPMrestoration
      )

      _RPMoption = Restore.restoreRPMdb

      Builtins.y2warning("RPMoption: %1", _RPMoption)

      if _RPMoption == nil
        # BNC #553400, Comment #19: Use the proposed 'Restore RPM DB' only if proposal is valid
        if Builtins.haskey(proposedRPMrestoration, "proposed") &&
            Ops.get_boolean(proposedRPMrestoration, "proposed", false) != nil
          _RPMoption = Ops.get_boolean(
            proposedRPMrestoration,
            "proposed",
            false
          )
        else
          _RPMoption = false
        end
      end

      Builtins.y2warning("RPMoption: %1", _RPMoption)

      _RPMoption = false if _RPMoption == nil

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          # table header
          Table(
            Id(:pkgtable),
            Opt(:notify),
            Header(
              " ",
              _("Files"),
              _("Package"),
              _("Version"),
              _("Description")
            ),
            tablecontents
          ),
          VSpacing(0.2),
          # push button label
          HBox(
            PushButton(Id(:select), _("&Select All")),
            PushButton(Id(:deselect), _("&Deselect All")),
            button
          ),
          VSpacing(1.0),
          # check box label - restore option
          CheckBox(
            Id(:rpmdb),
            Opt(:notify),
            _("Restore RPM &Database (if present in archive)"),
            _RPMoption
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      # description of symbols in the table 1/2
      helptext = _(
        "X: Restore all files from backup, P: Partial restore of manually selected files"
      )

      # description of symbols in the table 2/2
      helptext = Ops.add(
        helptext,
        _(
          "<P>To select files to restore from the archive, press <B>Select Files</B>.</P>"
        )
      )

      # dialog header
      Wizard.SetContents(
        _("Packages to Restore"),
        contents,
        RestoreSelectionHelp(false),
        true,
        true
      )

      if Mode.config == true
        Wizard.SetNextButton(:next, Label.FinishButton)
      else
        Wizard.SetNextButton(:next, Label.OKButton)
      end

      if Restore.RPMrestorable == false
        # RPM DB cannot be restored (it is not contained in the archive)
        Restore.restoreRPMdb = false

        UI.ChangeWidget(Id(:rpmdb), :Enabled, false)
        Builtins.y2warning(
          "RPM DB is not present in the archive - cannot be restored"
        )
      end


      # set currnet item in the table
      if Ops.greater_than(Builtins.size(tablecontents), 0)
        UI.ChangeWidget(Id(:pkgtable), :CurrentItem, position)
      end

      ret = nil
      begin
        ret = UI.UserInput

        current = 0
        current_value = ""
        current_pkgname = ""
        current_version = ""

        if Ops.greater_than(Builtins.size(tablecontents), 0)
          current = Convert.to_integer(
            UI.QueryWidget(Id(:pkgtable), :CurrentItem)
          )
          current_item = Convert.to_term(
            UI.QueryWidget(Id(:pkgtable), term(:Item, current))
          )
          current_value = Ops.get_string(current_item, 1, " ")
          current_pkgname = Ops.get_string(current_item, 3, "")
          current_version = Ops.get_string(current_item, 4, "") 
          # current_value   = (string) select((term) UI::QueryWidget(`id(`pkgtable), `Item(current)), 1, " ");
          # current_pkgname = (string) select((term) UI::QueryWidget(`id(`pkgtable), `Item(current)), 3, "");
          # current_version = (string) select((term) UI::QueryWidget(`id(`pkgtable), `Item(current)), 4, "");
        end

        @restorepackagename = current_pkgname

        # package name "none" - files not owned by any package
        current_pkgname = "" if current_pkgname == _("--No package--")

        if ret == :pkgtable
          # toggle restore selection: "X" -> " ", " " -> "X", "P" -> " "
          if current_value == " "
            # check if package is installed
            # TODO check versions
            if current_pkgname != "" &&
                !Builtins.haskey(
                  Restore.GetActualInstalledPackages,
                  current_pkgname
                ) &&
                !Builtins.haskey(@packagestoinstall, current_pkgname)
              current_value = InstallQuestion(current_pkgname, current_version) ? "X" : " "
            else
              current_value = "X"
            end
          else
            current_value = " "
          end

          # files are selected to restore - all
          selectionstring = current_value == "X" ? _("All") : ""

          UI.ChangeWidget(Id(:pkgtable), term(:Item, current, 0), current_value)
          UI.ChangeWidget(
            Id(:pkgtable),
            term(:Item, current, 1),
            selectionstring
          )

          Restore.SetRestoreSelection(
            current_pkgname,
            { "sel_type" => current_value }
          )
        elsif ret == :files
          # check if package is installed
          # TODO check versions
          if current_value == " " && current_pkgname != "" &&
              !Builtins.haskey(
                Restore.GetActualInstalledPackages,
                current_pkgname
              ) &&
              !Builtins.haskey(@packagestoinstall, current_pkgname)
            if InstallQuestion(current_pkgname, current_version) == false
              ret = :dummy
            end
          end

          @restorepackagename = current_pkgname
        elsif (ret == :select || ret == :deselect) &&
            Ops.greater_than(Builtins.size(tablecontents), 0)
          # set selection type
          sel_type = ret == :select ? "X" : " "

          if sel_type == "X"
            # check whether some packages are missing, ask if they should be selected too
            missing = Restore.GetMissingPackages
            selmissing = Mode.config # select all packages in autoinstall config mode

            if missing != {} && Mode.config == false
              # user selected to restore all packages,
              # but some packages are not installed
              # ask to restore them
              question = _(
                "Some packages are not installed.\nSelect them for restoration?\n"
              )
              selmissing = Popup.AnyQuestion(
                "",
                question,
                Label.YesButton,
                Label.NoButton,
                :focus_no
              )
            end

            # ask about mismatched packages
            mismatched = Restore.GetMismatchedPackages
            selmismatch = Mode.config # select all packages in autoinstall config mode

            if mismatched != {} && Mode.config == false
              # user selected to restore all packages,
              # but some installed packages have different version than at backup
              # ask to restore them
              question = _(
                "Some installed packages have a different\n" +
                  "version than in the backup archive.\n" +
                  "Select them for restoration?\n"
              )
              selmismatch = Popup.AnyQuestion(
                "",
                question,
                Label.YesButton,
                Label.NoButton,
                :focus_no
              )
            end

            # set selection type for packages
            Builtins.foreach(Restore.GetArchiveInfo) do |p, info|
              sel = sel_type
              if selmissing == false && Builtins.haskey(missing, p) == true
                sel = " "
              elsif selmismatch == false &&
                  Builtins.haskey(mismatched, p) == true
                sel = " "
              end
              Restore.SetRestoreSelection(
                p,
                { "sel_type" => sel, "sel_file" => [] }
              )
            end
          else
            # set selection type for all packages
            Builtins.foreach(Restore.GetArchiveInfo) do |p, info|
              Restore.SetRestoreSelection(
                p,
                { "sel_type" => sel_type, "sel_file" => [] }
              )
            end
          end

          # change table contents
          UI.ChangeWidget(
            Id(:pkgtable),
            :Items,
            CreateTableContentsRestoreSelection(Restore.GetArchiveInfo)
          )

          # set previous selection
          if current != nil
            UI.ChangeWidget(Id(:pkgtable), :CurrentItem, current)
          end
        elsif ret == :rpmdb
          # check current RPM rezstoration status with proposed
          selectedRPM = Convert.to_boolean(UI.QueryWidget(Id(:rpmdb), :Value))
          proposedRPMrestoration = Restore.ProposeRPMdbRestoration
          _RPMoption = Ops.get_boolean(proposedRPMrestoration, "proposed")

          if selectedRPM != _RPMoption
            # display warning

            if _RPMoption == true
              Popup.Warning(_("Restoring the RPM database is recommended."))
            elsif _RPMoption == false
              Popup.Warning(_("Not restoring the RPM database is recommended."))
            else
              # RPMoption is nil
              Popup.Warning(
                _(
                  "There is a conflict between selected\n" +
                    "packages and the RPM database restoration option.\n" +
                    "Try changing the selection or the RPM database restoration status."
                )
              )
            end

            Restore.restoreRPMdb = selectedRPM
          end
        elsif ret == :cancel
          ret = :abort
        end
      end while ret != :next && ret != :abort && ret != :back && ret != :files

      if ret == :next
        final = Restore.GetArchiveInfo

        final = Builtins.filter(final) do |p, i|
          Ops.get_string(i, "sel_type", " ") != " "
        end

        Restore.restoreRPMdb = Convert.to_boolean(
          UI.QueryWidget(Id(:rpmdb), :Value)
        )

        Builtins.y2debug("Final restore selection: %1", final)
      end

      Wizard.RestoreNextButton if Mode.config == true

      @lastret = Convert.to_symbol(ret)
      Convert.to_symbol(ret)
    end

    # Display all files in backup archive which belong to package. User can select which files will be resored.
    # @param [String] packagename Name of package
    # @return [Symbol] UI::UserInput() result
    def FileSelectionDialog(packagename)
      # create multiselection widget contents

      restore_info = Restore.GetArchiveInfo
      pkginfo = Ops.get_map(restore_info, packagename, {})
      # map pkginfo = lookup(Restore::GetArchiveInfo(), packagename, $[]);

      sel_type = Ops.get_string(pkginfo, "sel_type", " ")
      files = Ops.get_list(pkginfo, "files", [])
      sel_file = Ops.get_list(pkginfo, "sel_file", [])

      cont = []

      Builtins.foreach(files) do |f|
        selected = false
        if sel_type == "X"
          selected = true
        elsif sel_type == " "
          selected = false
        elsif sel_type == "P"
          selected = Builtins.contains(sel_file, f)
        else
          Builtins.y2error(
            "Unknown selection type %1 in package %2",
            sel_type,
            packagename
          )
        end
        cont = Builtins.add(cont, Item(Id(f), f, selected))
      end 


      # multi selection box label
      mlabel = _("&Files to Restore")

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          ReplacePoint(Id(:rp), MultiSelectionBox(Id(:mbox), mlabel, cont)),
          VSpacing(1),
          HBox(
            # push button label
            PushButton(Id(:all), _("&Select All")),
            # push button label
            PushButton(Id(:none), _("&Deselect All"))
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      Wizard.SetNextButton(:next, Label.OKButton)

      # dialog header - %1 is name of package (e.g. "aaa_base")
      Wizard.SetContents(
        Builtins.sformat(_("File Selection: Package %1"), packagename),
        contents,
        FileSelectionHelp(),
        true,
        true
      )

      ret = nil
      begin
        ret = UI.UserInput

        if ret == :all || ret == :none
          cont = []
          selected = ret == :all

          Builtins.foreach(files) do |f|
            cont = Builtins.add(cont, Item(Id(f), f, selected))
          end 


          UI.ReplaceWidget(Id(:rp), MultiSelectionBox(Id(:mbox), mlabel, cont))
        elsif ret == :cancel
          ret = :abort
        end
      end while ret != :next && ret != :abort && ret != :back

      if ret == :next
        sel_type_new = ""
        sel = Convert.to_list(UI.QueryWidget(Id(:mbox), :SelectedItems))

        if Builtins.size(sel) == 0
          sel_type_new = " "
        elsif Builtins.size(sel) == Builtins.size(files)
          sel_type_new = "X"
          # clear list of selected files to save memory, "X" as sel_type is enough
          sel = []
        else
          sel_type_new = "P"
        end

        Restore.SetRestoreSelection(
          packagename,
          { "sel_type" => sel_type_new, "sel_file" => sel }
        )
      end

      Wizard.RestoreNextButton

      Convert.to_symbol(ret)
    end

    # Restore packages from backup archive - display progress of restoring process
    # @return [Symbol] UI::UserInput() result
    def RestoreProgressDialog
      ret = nil
      progressbar = :progress

      bootloaderstep = Restore.runbootloader == true ? 1 : 0

      contents = HBox(
        HSpacing(2),
        VBox(
          VSpacing(1),
          ProgressBar(
            Id(progressbar),
            " ",
            Ops.add(Restore.TotalPackagesToRestore, bootloaderstep),
            0
          ),
          VSpacing(1.5)
        ),
        HSpacing(2)
      )

      # callback function for abort
      callback = lambda do
        Yast.import "Label"
        ret2 = UI.PollInput
        abort = false
        if ret2 == :abort || ret2 == :cancel
          # abort popup question
          abort = Popup.AnyQuestion(
            _("Abort Confirmation"),
            _("Really abort restore?"),
            Label.YesButton,
            Label.NoButton,
            :focus_no
          )
        end
        abort
      end

      # dialog header
      Wizard.SetContents(
        _("Restoring Files"),
        contents,
        RestoreProgressHelp(),
        false,
        false
      )

      # start restoration
      result = Restore.Write(callback, progressbar, Restore.targetDirectory)

      # set values from restoration
      ret = Ops.get_boolean(result, "aborted", false) ? :abort : :next

      # get lilo status
      @bloaderstatus = Ops.get_boolean(result, "bootloader", false)

      if ret == :next
        @restoredfiles = Ops.get_list(result, "restored", [])
        @failedfiles = Ops.get_list(result, "failed", [])
        @restoredpackages = Ops.get_integer(result, "packages", 0)
      end

      @lastret = ret
      ret
    end

    # This function should be called only once before end of client. This function
    # cleans up the system - unmounts mounted files systems.
    # @return [Symbol] Returns symbol `next for wizard sequencer

    def AtExit
      # unmount file system
      Restore.Umount

      :next
    end

    # Convert programm status to string
    # @param [Boolean] status Status: true = OK, false = Failed, nil = "Not started"
    # @return [String] Status

    def StatusToString(status)
      # program return status - program was not started
      ret = "<I>" + _("Not started") + "</I>"

      if status == true
        # program return status - success
        ret = _("OK")
      elsif status == false
        # program return status - failed
        ret = "<B>" + _("Failed") + "</B>"
      end

      ret
    end


    # Display summary of restoration
    # @return [Symbol] UI::UserInput() result
    def SummaryDialog
      # summary information texts
      basicinfo = Ops.add(
        Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(
                        Ops.add(
                          Ops.add(
                            "<P>" + _("Number of Installed Packages: "),
                            Builtins.size(@packagestoinstall)
                          ),
                          "<BR>"
                        ),
                        _("Number of Uninstalled Packages: ")
                      ),
                      Builtins.size(@packagestouninstall)
                    ),
                    "</P><P>"
                  ),
                  _("Total Restored Packages: ")
                ),
                @restoredpackages
              ),
              "<BR>"
            ),
            _("Total Restored Files: ")
          ),
          @restoredfiles != nil ? Builtins.size(@restoredfiles) : 0
        ),
        "</P>"
      )

      # display failed files if any
      if Ops.greater_than(Builtins.size(@failedfiles), 0)
        # summary information text - header
        basicinfo = Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(Ops.add(basicinfo, "<P><B>"), _("Failed Files")),
              "</B><BR>"
            ),
            Builtins.mergestring(@failedfiles, "<BR>")
          ),
          "</P>"
        )
      end

      # set lilo result string
      lilostr = StatusToString(@bloaderstatus)

      filelist = ""

      if @restoredfiles != nil &&
          Ops.greater_than(Builtins.size(@restoredfiles), 0)
        prefix = Restore.targetDirectory

        if Builtins.substring(prefix, Ops.subtract(Builtins.size(prefix), 1), 1) != "/"
          prefix = Ops.add(prefix, "/")
        end

        filelist = Ops.add(
          prefix,
          Builtins.mergestring(@restoredfiles, Ops.add("<BR>", prefix))
        )
      end

      # summary information texts - details
      extendedinfo = Ops.add(
        Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  "<P><BR><B>" + _("Details:") + "</B></P><P>" +
                    _("Boot Loader Configuration: "),
                  lilostr
                ),
                " </P><P><B>"
              ),
              _("Restored Files:")
            ),
            "</B><BR>"
          ),
          filelist
        ),
        "</P>"
      )

      # dialog header
      DisplaySummaryDialog(
        basicinfo,
        Ops.add(basicinfo, extendedinfo),
        SummaryHelp(),
        _("Summary of Restoration"),
        :finish
      )
    end

    # Whole restoration
    # @return [Object] Returned value from Sequencer::Run() call
    def RestoreSequence
      aliases = {
        "archive"    => lambda { ArchiveSelectionDialog(false, false, "") },
        "property"   => lambda { ArchivePropertyDialog() },
        "marchive"   => [lambda { ArchiveSelectionDialog(true, true, "") }, true],
        "contents"   => [lambda { ArchiveContentsDialog() }, true],
        "options"    => [lambda { RestoreOptionsDialog() }, true],
        "install"    => lambda { SelectionInstallDialog() },
        "uninstall"  => lambda { SelectionUninstallDialog() },
        "sw_single"  => lambda { SWsingleDialog() },
        "select"     => lambda { PackageSelectionRestoreDialog() },
        "selectfile" => [lambda { FileSelectionDialog(@restorepackagename) }, true],
        "restore"    => [lambda { RestoreProgressDialog() }, true],
        "atexit"     => lambda { AtExit() },
        "summary"    => lambda { SummaryDialog() }
      }

      sequence = {
        "ws_start"   => "archive",
        "archive"    => {
          :next     => "property",
          :noconfig => "atexit",
          :abort    => "atexit"
        },
        "marchive"   => { :next => "install", :abort => "atexit" },
        "property"   => {
          :details => "contents",
          :options => "options",
          :multi   => "marchive",
          :next    => "install",
          :abort   => "atexit"
        },
        "contents"   => { :next => "property", :abort => "atexit" },
        "options"    => { :next => "property", :abort => "atexit" },
        "install"    => { :next => "uninstall", :abort => "atexit" },
        "uninstall"  => { :next => "sw_single", :abort => "atexit" },
        "sw_single"  => { :next => "select", :abort => "atexit" },
        "select"     => {
          :files => "selectfile",
          :abort => "atexit",
          :next  => "restore"
        },
        "restore"    => { :next => "summary", :abort => "atexit" },
        "selectfile" => { :next => "select", :abort => "atexit" },
        "summary"    => { :abort => "atexit", :next => "atexit" },
        "atexit"     => { :next => :next }
      }


      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("restore")

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      ret
    end



    # Restoration without reading and writing.
    # For use with autoinstallation.
    # @return [Object] Returned value from Sequencer::Run() call
    def RestoreAutoSequence
      aliases = {
        "archive"    => lambda { ArchiveSelectionDialog(false, false, "") },
        "property"   => lambda { ArchivePropertyDialog() },
        "marchive"   => [lambda { ArchiveSelectionDialog(true, true, "") }, true],
        "contents"   => [lambda { ArchiveContentsDialog() }, true],
        "options"    => [lambda { RestoreOptionsDialog() }, true],
        "select"     => lambda { PackageSelectionRestoreDialog() },
        "atexit"     => lambda { AtExit() },
        "selectfile" => [lambda { FileSelectionDialog(@restorepackagename) }, true]
      }

      sequence = {
        "ws_start"   => "archive",
        "archive"    => {
          :next     => "property",
          :noconfig => "atexit",
          :abort    => :abort
        },
        "marchive"   => { :next => "select", :abort => :abort },
        "property"   => {
          :details => "contents",
          :options => "options",
          :multi   => "marchive",
          :next    => "select",
          :abort   => :abort
        },
        "contents"   => { :next => "property", :abort => :abort },
        "options"    => { :next => "property", :abort => :abort },
        "select"     => {
          :files => "selectfile",
          :abort => :abort,
          :next  => :next
        },
        "selectfile" => { :next => "select", :abort => :abort },
        "atexit"     => { :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("restore")

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      deep_copy(ret)
    end


    # Return content for table widget - list of backup files
    # @param [Hash <String, Hash{String => Object>}] packagesinfo Map $[ "packagename" : $[ "files" : ["files in the archive"] ] ]
    # @return [Array] Table content
    def CreateArchiveContentTable(packagesinfo)
      packagesinfo = deep_copy(packagesinfo)
      ret = []
      num = 0

      Builtins.foreach(packagesinfo) do |p, info|
        files = Ops.get_list(info, "files", [])
        version = Ops.get_string(info, "vers", "")
        Builtins.foreach(files) do |file|
          ret = Builtins.add(ret, Item(Id(num), p, version, file))
          num = Ops.add(num, 1)
        end
      end if packagesinfo != nil

      deep_copy(ret)
    end

    # Select item from list
    # @param [String] label Label in dialog
    # @param [Array] inputlist List of values
    # @param [String] selected Default selected value
    # @return [String] Selected value or empty string ("") if dialog was closed

    def SelectFromList(label, inputlist, selected)
      inputlist = deep_copy(inputlist)
      UI.OpenDialog(
        HBox(
          VSpacing(10),
          VBox(
            HSpacing(40),
            SelectionBox(Id(:selbox), label, inputlist),
            ButtonBox(
              PushButton(Id(:ok), Opt(:default), Label.OKButton),
              PushButton(Id(:cancel), Label.CancelButton)
            )
          )
        )
      )

      if Builtins.contains(inputlist, selected)
        UI.ChangeWidget(Id(:selbox), :CurrentItem, selected)
      end

      UI.SetFocus(Id(:ok))

      uinput = nil
      begin
        uinput = UI.UserInput
      end while uinput != :ok && uinput != :cancel

      ret = uinput == :cancel ?
        "" :
        Convert.to_string(UI.QueryWidget(Id(:selbox), :CurrentItem))

      UI.CloseDialog

      ret
    end
  end
end
