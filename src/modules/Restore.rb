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
#  * File:
#  *   modules/Restore.ycp
#  *
#  * Package:
#  *   Restore module
#  *
#  * Summary:
#  *   Data for configuration of restore, input and output functions.
#  *
#  * Authors:
#  *   Ladislav Slezak <lslezak@suse.cz>
#  *
#  * $Id$
#
#  * Representation of the configuration of restore.
#  * Input and output routines.
#  *
require "yast"

module Yast
  class RestoreClass < Module
    def main
      Yast.import "UI"
      Yast.import "Pkg"

      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Mode"
      Yast.import "Summary"
      Yast.import "Service"
      Yast.import "Package"
      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "URL"
      Yast.import "Message"
      Yast.import "String"

      textdomain "restore"

      # local file name (can be on mounted file system)
      @filename = ""

      # entered file name (e.g. nfs://server:/dir/archive.tar)
      @inputname = ""

      @completerestoration = false

      # list of volumes in URL-like syntax
      @inputvolumes = []

      # contents of archive
      @archivefiles = []

      # installed packages at backup time
      @installedpkgs = {}

      # list of installed packages
      @actualinstalledpackages = {}

      @complete_backup = []

      # restoration archive and selection
      # "vers" : "version", "files" : ["files"], "prefix" : "prefix", "descr" : "description", "sel_type" : "X", "sel_file" : [""]
      @archive_info = {}

      @autoinst_info = {}

      # information stored in archive
      @date = ""
      @hostname = ""
      @comment = ""

      # list of files
      @volumeparts = []

      # temporary directory
      @tempdir = ""

      # restore files to the selected directory
      @targetDirectory = "/"

      # mount point, stored for unmounting
      @mountpoint = ""

      # nopackage identification stored in Exported map
      # (to prevent empty tag in XML profile)
      @nopackage_id = "_NoPackage_"

      # Run lilo after files are restored
      @runbootloader = true

      # Rewrite RPM db - unapack /var/lib/rpm/* files from backup if present
      @restoreRPMdb = nil


      @config_modified = false
    end

    # Return modified flag
    # @return true if modified
    def Modified
      @config_modified
    end

    def SetModified
      @config_modified = true

      nil
    end

    # Selected archive has more parts
    # @return boolen True if archive have more than one part.
    def IsMultiVolume
      Ops.greater_than(Builtins.size(@volumeparts), 0)
    end

    # Return date when backup archive was created. Date is stored in archive in file info/date.
    # @return [String] Date
    def GetArchiveDate
      @date
    end

    # Return name of backup archive
    # @return [String] Input name file name
    def GetInputName
      @inputname
    end

    # Return name of backup archive
    # @return [String] File name
    def GetArchiveName
      @filename
    end

    # Return user comment stored in archive. Comment is stored in file info/comment.
    # @return [String] Archive comment
    def GetArchiveComment
      @comment
    end

    # Return host name of machine on which backup archive was created. Host name is stored in archive in file info/hostname.
    # @return [String] Host name
    def GetArchiveHostname
      @hostname
    end

    # Return map with packages installed at backup time (form is $["package name" : "version"]).
    # @return [Hash] Installed packages at backup time
    def GetArchiveInstalledPackages
      deep_copy(@installedpkgs)
    end

    # Return list of files in the backup archive
    # @return [Array] Files in the archive
    def GetArchiveFiles
      deep_copy(@archivefiles)
    end


    # Read installed packages.
    # @return [Hash] Map $[ "packagename" : "version" ]
    def ReadActualInstalledPackages
      # do not read installed packages in autoyast config mode
      return {} if Mode.config == true

      # init packager (TODO: later should be removed...)
      Pkg.TargetInit("/", false)

      # read info about installed packages
      info = Pkg.GetPackages(:installed, false)
      Builtins.y2debug("ReadActualInstalledPackages: %1", Builtins.sort(info))

      # process version info
      ret = {}

      Builtins.foreach(info) do |pkg|
        all = Builtins.splitstring(pkg, " ")
        ret = Builtins.add(
          ret,
          Ops.get(all, 0, "unknown"),
          Ops.add(Ops.add(Ops.get(all, 1, ""), "-"), Ops.get(all, 2, ""))
        )
      end 


      deep_copy(ret)
    end

    # Return installed packages. Result is cached in Restore module, so only first use takes long time
    # @return [Hash] Map $[ "packagename" : "version" ]
    def GetActualInstalledPackages
      if @actualinstalledpackages == {} || @actualinstalledpackages == nil
        @actualinstalledpackages = ReadActualInstalledPackages()
      end

      deep_copy(@actualinstalledpackages)
    end


    # Return missing packages (packages which were installed at backup time, but at restore time they are not installed)
    # @return [Hash] Map $[ "packagename" : $[ "ver" : "version", "descr" : "Short description of the package"]], key description is present only if decription exists
    def GetMissingPackages
      r = {}

      GetActualInstalledPackages()

      # filter actual installed packages out
      r = Builtins.filter(@installedpkgs) do |p, v|
        Builtins.haskey(@actualinstalledpackages, p) != true
      end

      Builtins.y2debug("actualinstalledpackages: %1", @actualinstalledpackages)
      Builtins.y2debug("GetMissingPackages r: %1", r)

      # add descriptions
      ret = Builtins.mapmap(r) do |pkg, version|
        descr = Mode.test == false ? Pkg.PkgSummary(pkg) : ""
        if descr == nil
          next { pkg => { "ver" => version } }
        else
          next { pkg => { "ver" => version, "descr" => descr } }
        end
      end

      # ignore gpg-pubkey packages - they are not real RPMs
      ret = Builtins.filter(ret) { |pkg, inf| pkg != "gpg-pubkey" }

      Builtins.y2debug("GetMissingPackages ret: %1", ret)

      deep_copy(ret)
    end

    # Return extra packages (packages which are installed at restore time, but at restore time they are installed)
    # @return [Hash] Map $[ "packagename" : $[ "ver" : "version", "descr" : "Short description of the package"]], key description is present only if decription exists
    def GetExtraPackages
      r = {}

      GetActualInstalledPackages()

      # filter actual installed packages out
      r = Builtins.filter(@actualinstalledpackages) do |p, v|
        Builtins.haskey(@installedpkgs, p) != true
      end

      # add descriptions
      ret = Builtins.mapmap(r) do |pkg, version|
        descr = Mode.test == false ? Pkg.PkgSummary(pkg) : ""
        if descr == nil
          next { pkg => { "ver" => version } }
        else
          next { pkg => { "ver" => version, "descr" => descr } }
        end
      end

      deep_copy(ret)
    end

    # Return packages which have different version at backup archive and in system
    # @return [Hash] Map $[ "packagename" : $[ "inst": "installed version", "ver" : "version at backup time, "descr" : "Short description of the package"]], key description is present only if decription exists
    def GetMismatchedPackages
      ret = {}

      GetActualInstalledPackages()

      Builtins.foreach(@actualinstalledpackages) do |p, v|
        if Builtins.haskey(@installedpkgs, p) == true
          backupversion = Ops.get(@installedpkgs, p, "")

          if backupversion != v
            descr = Mode.test == false ? Pkg.PkgSummary(p) : ""

            ret = descr != nil ?
              Builtins.add(
                ret,
                p,
                { "ver" => backupversion, "inst" => v, "descr" => descr }
              ) :
              Builtins.add(ret, p, { "ver" => backupversion, "inst" => v })
          end
        end
      end 


      deep_copy(ret)
    end

    # Returns selected packages (even partially).
    # @return [Hash] Map with same keys as map returned by GetArchiveInfo()

    def GetSelectedPackages
      ret = {}

      if @archive_info != nil
        # filter out unselected packages
        ret = Builtins.filter(@archive_info) do |p, info|
          sel_type = Ops.get_string(info, "sel_type", " ")
          if sel_type == "X" || sel_type == "P"
            next true
          else
            next false
          end
        end
      end

      deep_copy(ret)
    end

    # Clear cache of installed packages. Next use of GetActualInstalledPackages() function will reread installed packages.
    def ClearInstalledPackagesCache
      @actualinstalledpackages = nil

      nil
    end

    # Umount mounted file system.

    def Umount
      if @mountpoint != "" && @mountpoint != nil
        Builtins.y2milestone("Umount called - unmounting %1", @mountpoint)
        SCR.Execute(path(".target.umount"), @mountpoint)
        @mountpoint = ""
      end

      nil
    end

    # Access to file on NFS server
    # @param [String] server Name or IP adress of NFS server
    # @param [String] file File on the server
    # @return [Hash] $[ "mounted" : boolena (true on success), "mountpoint" : string (mount point) , "file" : string (file name), "server_dir" : string (directory on the server) ]

    def mountNFS(server, file)
      pos = Builtins.findlastof(file, "/")

      if pos != nil
        dir = Builtins.substring(file, 0, pos)
        f = Builtins.substring(file, Ops.add(pos, 1))

        tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
        mpoint = Ops.add(tmpdir, "/nfs")

        dir = "/" if dir == "" || dir == nil

        # create mount point directory
        SCR.Execute(path(".target.mkdir"), mpoint)

        Builtins.y2milestone("dir: %1", dir)
        Builtins.y2milestone("file: %1", f)
        Builtins.y2milestone("mpoint: %1", mpoint)

        # BNC #682064: also 'nolock' is required
        result = Convert.to_boolean(
          SCR.Execute(
            path(".target.mount"),
            [Ops.add(Ops.add(server, ":"), dir), mpoint],
            "-t nfs -o ro,nolock"
          )
        )

        return {
          "mounted"    => result,
          "mountpoint" => mpoint,
          "file"       => f,
          "server_dir" => dir
        }
      end

      { "mounted" => false }
    end


    # Access to file on CD
    # @param [Fixnum] cdindex Index of CD drive (in list SCR::Read(.probe.cdrom))
    # @return [Hash] $[ "mounted" : boolena (true on success), "mpoint" : string (mount point) ]

    def mountCD(cdindex)
      drives = Convert.to_list(SCR.Read(path(".probe.cdrom")))

      if cdindex == nil ||
          Ops.greater_than(cdindex, Ops.subtract(Builtins.size(drives), 1))
        return { "mounted" => false }
      end

      cddevice = Ops.get_string(drives, [cdindex, "dev_name"], "/dev/cdrom")
      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      mpoint = Ops.add(tmpdir, "/cd")

      # create mount point directory
      SCR.Execute(path(".target.mkdir"), mpoint)

      result = Convert.to_boolean(
        SCR.Execute(path(".target.mount"), [cddevice, mpoint], "-o ro")
      )

      { "mounted" => result, "mpoint" => mpoint }
    end


    # Access to file on floppy
    # @param [Fixnum] fdindex Index of floppy drive (in list SCR::Read(.probe.floppy))
    # @return [Hash] $[ "mounted" : boolena (true on success), "mpoint" : string (mount point) ]

    def mountFloppy(fdindex)
      drives = Convert.to_list(SCR.Read(path(".probe.floppy")))

      if fdindex == nil ||
          Ops.greater_than(fdindex, Ops.subtract(Builtins.size(drives), 1))
        return { "mounted" => false }
      end

      fddevice = Ops.get_string(drives, [fdindex, "dev_name"], "/dev/fd0")
      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      mpoint = Ops.add(tmpdir, "/fd")

      # create mount point directory
      SCR.Execute(path(".target.mkdir"), mpoint)

      result = Convert.to_boolean(
        SCR.Execute(path(".target.mount"), [fddevice, mpoint], "-o ro")
      )

      { "mounted" => result, "mpoint" => mpoint }
    end


    # Mount device
    # @param [String] device Device file name (e.g. /dev/cdrom, /dev/sda...)
    # @return [Hash] Map $[ "mounted" : boolean (true on success), "mpoint" : string (mount point where device was mounted) ];

    def mountDevice(device)
      return { "mounted" => false } if device == nil || device == ""

      tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      mpoint = Ops.add(tmpdir, "/mount")

      # create mount point directory
      SCR.Execute(path(".target.mkdir"), mpoint)

      # mount read-only
      result = Convert.to_boolean(
        SCR.Execute(path(".target.mount"), [device, mpoint], "-o ro")
      )

      { "mounted" => result, "mpoint" => mpoint }
    end

    # Checks whether the portmapper service is installed and started.
    # Installs and/or starts the service otherwise.

    def CheckAndPrepareNFS(parsed_url)
      parsed_url = deep_copy(parsed_url)
      ret = false

      # both new and old services are supported (portmap got replaced by rpcbind)
      # names of packages and service names match
      Builtins.foreach(["rpcbind", "portmap"]) do |portmapper|
        # checking if rpcbind is installed
        package_installed = Convert.to_integer(
          SCR.Execute(
            path(".target.bash"),
            Builtins.sformat("/bin/rpm -q %1", portmapper)
          )
        )
        Builtins.y2milestone(
          "%1 is instaled: %2",
          portmapper,
          package_installed
        )
        if package_installed != 0
          Builtins.y2milestone("%1 package is not installed", portmapper)
          installed = Package.DoInstall([portmapper])
          Builtins.y2milestone(
            "Package %1 installed: %2",
            portmapper,
            installed
          )

          # try next service
          next if installed != true
        end
        # checking if portmapper is running
        portmapper_status = Service.Status(portmapper)
        Builtins.y2milestone("portmap status: %1", portmapper_status)
        # portmapper is running
        if portmapper_status == 0
          ret = true
        else
          # start portmapper
          started = Service.Start(portmapper)
          Builtins.y2milestone("%1 start result: %2", portmapper, started)
          ret = started
        end
        raise Break if ret == true
      end

      ret
    end

    # Mount input source
    # @param [String] input File in URl-like syntax
    # @return [Hash] Map $[ "success" : boolean (true on success), "mpoint" : string (mount point), "file" : string (file name on the local system) ];

    def MountInput(input)
      Builtins.y2milestone("MountInput(%1)", input)

      success = false
      mpoint = ""
      file = ""

      #parse 'input'
      nfsprefix = "nfs://"
      fileprefix = "file://"
      devprefix = "dev://"
      cdprefix = "cd" # cd prefix can be "cd://" (equivalent to "cd0://"), "cd1://", "cd2://", ... number of CD identification
      fdprefix = "fd"

      parsed_url = URL.Parse(input)
      scheme = Ops.get_string(parsed_url, "scheme", "file")

      if scheme == "nfs"
        if CheckAndPrepareNFS(parsed_url)
          Builtins.y2milestone("NFS-related services adjusted")
        else
          Builtins.y2error("Cannot adjust NFS-related services")
        end

        Builtins.y2milestone(
          "NFS source - server: %1  file: %2",
          Ops.get_string(parsed_url, "host", ""),
          Ops.get_string(parsed_url, "path", "")
        )
        mountresult = mountNFS(
          Ops.get_string(parsed_url, "host", ""),
          Ops.get_string(parsed_url, "path", "")
        )

        if Ops.get_boolean(mountresult, "mounted", false) == false
          Builtins.y2error("Cannot read source '%1' - NFS mount failed", input)
        else
          mpoint = Ops.get_string(mountresult, "mountpoint", "")
          file = Ops.add(
            Ops.add(mpoint, "/"),
            Ops.get_string(mountresult, "file", "")
          )
          success = true

          Builtins.y2milestone("mpoint: %1", mpoint)
          Builtins.y2milestone("file: %1", file)
        end
      elsif scheme == "dev"
        device = Ops.get_string(parsed_url, "host", "")
        devfile = Ops.get_string(parsed_url, "path", "")

        Builtins.y2milestone(
          "Device source - device: %1  file: %2",
          device,
          devfile
        )

        mountresult = mountDevice(device)

        if Ops.get_boolean(mountresult, "mounted", false) == false
          Builtins.y2error(
            "Cannot read source '%1' - device mount failed",
            input
          )
        else
          mpoint = Ops.get_string(mountresult, "mpoint", "")
          file = Ops.add(Ops.add(mpoint, "/"), devfile)
          success = true
        end
      elsif scheme == "file"
        file = Builtins.substring(input, Builtins.size(fileprefix))
        Builtins.y2milestone("FILE source: %1", file)

        success = true
      elsif Builtins.regexpmatch(scheme, "^cd[0-9]*")
        # get CD drive index
        cdindex = Builtins.regexpsub(scheme, "^cd0*([0-9]*)", "\\1")
        cdfile = Ops.get_string(parsed_url, "path", "")

        cdindex = "0" if cdindex == nil || cdindex == ""

        cdfile = "" if cdfile == nil

        Builtins.y2milestone("CD source - drive: %1  file: %2", cdindex, cdfile)

        # mount CD
        mountresult = mountCD(Builtins.tointeger(cdindex))

        if Ops.get_boolean(mountresult, "mounted", false) == false
          Builtins.y2error("Cannot read source '%1' - mount failed", input)
        else
          mpoint = Ops.get_string(mountresult, "mpoint", "")
          file = Ops.add(Ops.add(mpoint, "/"), cdfile)
          success = true
        end
      elsif Builtins.regexpmatch(scheme, "^fd[0-9]*")
        # get floppy index
        fdindex = Builtins.regexpsub(scheme, "fd0*([0-9]*)://(.*)", "\\1")
        fdfile = Ops.get_string(parsed_url, "path", "")

        fdindex = "0" if fdindex == nil || fdindex == ""

        fdfile = "" if fdfile == nil

        Builtins.y2milestone(
          "Floppy source - drive: %1  file: %2",
          fdindex,
          fdfile
        )

        # mount floppy
        mountresult = mountFloppy(Builtins.tointeger(fdindex))

        if Ops.get_boolean(mountresult, "mounted", false) == false
          Builtins.y2error("Cannot read source '%1' - mount failed", input)
        else
          mpoint = Ops.get_string(mountresult, "mpoint", "")
          file = Ops.add(Ops.add(mpoint, "/"), fdfile)
          success = true
        end
      else
        Builtins.y2error("Unknown prefix in input: %1", input)
      end

      { "success" => success, "mpoint" => mpoint, "file" => file }
    end


    # Check if volume number in archive is equal to expected volume number
    # @param [String] filename Volume file name
    # @param [Fixnum] num Number of volume
    # @return [Hash] Map $[ "success" : boolean (true on success), "lastvolume" : boolean (true if archive is last volume) ]

    def CheckVolume(filename, num)
      success = false
      lastvolume = true

      # test if archive is multi volume - use -v parameter to get file descriptions
      detailresult = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add(Ops.add("/bin/tar -v -t -f '", String.Quote(filename)), "'")
        )
      )

      stdout = Builtins.splitstring(
        Ops.get_string(detailresult, "stdout", ""),
        "\n"
      )
      firstline = Ops.get(stdout, 0, "")

      Builtins.y2debug("Test: First line: %1", firstline)

      # check if first line is volume label number num
      if Builtins.regexpmatch(
          firstline,
          Builtins.sformat("V--------- .* YaST2 backup: Volume %1--.*--", num)
        ) == true
        success = true
      end

      {
        "success"    => success,
        "lastvolume" => Ops.get_integer(detailresult, "exit", -1) == 0
      }
    end


    # Copy volume to the local temporary directory
    # @param [String] filename Source file
    # @param [Fixnum] num Number of volume
    # @return [Hash] Map $[ "success" : boolean (true on success), "file" : string (file name in the temporary directory) ]

    def CopyVolume(filename, num)
      success = false
      tmpfile = Ops.add(
        Ops.add(Ops.add(@tempdir, "/"), Builtins.sformat("%1", num)),
        ".tar"
      )

      # copy multi volume part to temp directory
      exit = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Ops.add(
            Ops.add(
              Ops.add(Ops.add("/bin/cp '", String.Quote(filename)), "' '"),
              String.Quote(tmpfile)
            ),
            "'"
          )
        )
      )

      if exit == 0
        success = true
      else
        Builtins.y2error("Copy failed")
      end

      { "success" => success, "file" => tmpfile }
    end


    # Add next volume - check volume, copy volume to the temp. dir.
    # @param [String] file File name of volume
    # @return [Hash] Map $[ "success" : boolean (true on success), "lastvolume" : boolean (true if archive is last volume) ]

    def AddVolume(file)
      vol = Ops.add(Builtins.size(@volumeparts), 1)
      success = false

      # check if file is next volume
      check = CheckVolume(file, vol)

      Builtins.y2debug("CheckVolume(%1, %2): %3", file, vol, check)

      if Ops.get_boolean(check, "success", false) == true
        # copy file to temporary directory
        copy = CopyVolume(file, vol)
        Builtins.y2debug("CopyVolume(%1, %2): %3", file, vol, copy)

        if Ops.get_boolean(copy, "success", false) == true
          partname = Ops.get_string(copy, "file", "")

          @volumeparts = Builtins.add(@volumeparts, partname)

          success = true
        end
      end

      {
        "success"    => success,
        "lastvolume" => Ops.get_boolean(check, "lastvolume", true)
      }
    end

    # Change restore selection of package.
    # @param pkgnames Name of package
    # @param [Hash] selection New restore selection for package, map  $[ "sel_type" : "X", "sel_file" : ["files"] ]
    def SetRestoreSelection(pkgname, selection)
      selection = deep_copy(selection)
      pkgname = "" if pkgname == @nopackage_id

      if Builtins.haskey(@archive_info, pkgname) == false
        Builtins.y2warning(
          "Package %1 is not in archive, cannot be restored!",
          pkgname
        )
      else
        sel_type = Ops.get_string(selection, "sel_type", " ")
        sel_file = []
        pkginfo = Ops.get(@archive_info, pkgname, {})

        pkginfo = {} if pkginfo == nil

        if sel_type == "P"
          sel_file = Ops.get_list(selection, "sel_file", [])
        elsif sel_type != "X" && sel_type != " "
          Builtins.y2warning(
            "Unknown selection type '%1' for package '%2'",
            sel_type,
            pkgname
          )
        end

        pkginfo = Builtins.add(pkginfo, "sel_type", sel_type)
        pkginfo = Builtins.add(pkginfo, "sel_file", sel_file)

        @archive_info = Builtins.add(@archive_info, pkgname, pkginfo)
      end

      nil
    end


    # Set selection in _auto client and display properties of archive
    # @param [Hash{String => map}] settings Restoration selection

    def SetSelectionProperty(settings)
      settings = deep_copy(settings)
      # set selection for this archive and display archive propertyt
      Builtins.foreach(settings) do |package, info|
        Builtins.y2debug(
          "setting selection: package:%1, selection:%2)",
          package,
          info
        )
        package = "" if package == @nopackage_id
        SetRestoreSelection(package, info)
      end

      nil
    end



    # Read contents of archive
    # @param [String] input File name of backup archive. File on NFS server is 'nfs://server:/dir/file.tar', local file: 'file:///dir/file.tar' (prefix is file://, directory is /dir)
    # @return [Boolean] True if archive was succesfully read, otherwise false (file does not exist, not tar archive, broken archive, archive not created by Backup module, ...)
    def Read(input)
      # umount old mount point
      Umount()

      if @tempdir == ""
        @tempdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      end

      @inputname = input

      if Mode.test == true
        @filename = "/tmp/dummy.tar"

        @archivefiles = [
          "info/",
          "info/date",
          "info/comment",
          "info/files",
          "info/packages_info",
          "info/installed_packages",
          "info/hostname",
          "NOPACKAGE-20020509-0.tar.gz",
          "kdebase3-3.0-19-20020509-0.tar.gz",
          "lprng-3.8.5-49-20020509-0.tar.gz",
          "mozilla-0.9.8-54-20020509-0.tar.gz",
          "netcfg-2002.3.20-0-20020509-0.tar.gz"
        ]

        @date = "13.01.2002 14:25"
        @comment = "Some comments"
        @hostname = "linux.local"

        @installedpkgs = {
          "netcfg"        => "2002.3.20-0",
          "lprng"         => "3.8.5-49",
          "kdebase3"      => "3.0-19",
          "gnome-applets" => "1.4.0.5-98",
          "mozilla"       => "0.9.8-54"
        }
        @actualinstalledpackages = {
          "ggv"      => "1.1.93-167",
          "netcfg"   => "2002.3.20-0",
          "lprng"    => "3.8.5-49",
          "kdebase3" => "3.0-19",
          "aterm"    => "0.4.0"
        }

        @archive_info = {
          ""         => {
            "descr"    => "Files not owned by any package",
            "files"    => ["/.qt/", "/dev/dvd", "/dev/cdrom"],
            "sel_type" => "X"
          },
          "kdebase3" => {
            "descr"    => "KDE base package: base system",
            "files"    => ["/etc/opt/kde3/share/config/kdm/kdmrc"],
            "prefix"   => "",
            "sel_type" => "X",
            "vers"     => "3.0-19"
          },
          "mozilla"  => {
            "descr"    => "Open Source WWW browser",
            "files"    => ["/opt/mozilla/chrome/installed-chrome.txt"],
            "prefix"   => "",
            "sel_type" => "X",
            "vers"     => "0.9.8-54"
          },
          "lprng"    => {
            "descr"    => "LPRng Print Spooler",
            "files"    => ["/etc/init.d/lpd"],
            "prefix"   => "",
            "sel_type" => "X",
            "vers"     => "3.8.5-49"
          },
          "netcfg"   => {
            "descr"    => "Network configuration files in /etc",
            "files"    => [
              "/etc/HOSTNAME",
              "/etc/defaultdomain",
              "/etc/exports",
              "/etc/hosts"
            ],
            "prefix"   => "",
            "sel_type" => "X",
            "vers"     => "2002.3.20-0"
          }
        }

        # set default selection
        @archive_info = Builtins.mapmap(@archive_info) do |p, i|
          i = Builtins.add(
            i,
            "sel_type",
            p == "" ?
              "X" :
              Builtins.haskey(@actualinstalledpackages, p) ? "X" : " "
          )
          { p => i }
        end

        return true
      end

      # mount source
      mresult = MountInput(input)

      Builtins.y2debug("MountInput: %1", mresult)

      if Ops.get_boolean(mresult, "success", false) == false
        # error message
        Report.Error(_("Cannot mount file system."))
        return false
      end

      @filename = Ops.get_string(mresult, "file", "")
      @mountpoint = Ops.get_string(mresult, "mpoint", "")

      Builtins.y2milestone("filename: %1", @filename)
      Builtins.y2milestone("mountpoint: %1", @mountpoint)

      # get archive contents
      result = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add(Ops.add("/bin/tar -t -f '", String.Quote(@filename)), "'")
        )
      )

      # check tar exit value
      if Ops.get_integer(result, "exit", -1) != 0
        # tar failed, check whether file is first volume of multivolume archive
        @volumeparts = []
        addresult = AddVolume(@filename)

        if Ops.get_boolean(addresult, "success", false) == true
          # read archive info from local copy (should be faster)
          @filename = Ops.get(@volumeparts, 0, "")
        else
          # error message
          Report.Error(
            _(
              "Cannot read archive file.\nIt is not a tar archive or it is broken.\n"
            )
          )
          return false
        end
      else
        # if archive is not local or NFS file copy it to tempdir (even if it isn't multi volume),
        # so removable device (e.g. CD-ROM) can be used for package installation later
        if Builtins.substring(input, 0, Builtins.size("file://")) != "file://" &&
            Builtins.substring(input, 0, Builtins.size("nfs://")) != "nfs://"
          # copy archive to local file
          copy = CopyVolume(@filename, 0)

          if Ops.get_boolean(copy, "success", false) == true
            # set file name to local copy
            @filename = Ops.get_string(copy, "file", "")

            # umount file system
            Umount()
          else
            # error message: copy failed
            Report.Error(
              _("Cannot copy archive file\nto temporary directory.\n")
            )
            return false
          end
        end
      end

      # get list of files
      @archivefiles = Builtins.splitstring(
        Ops.get_string(result, "stdout", ""),
        "\n"
      )
      @archivefiles = Builtins.filter(@archivefiles) { |f| f != "" && f != nil }

      compressed_packages_info = Builtins.contains(
        @archivefiles,
        "info/packages_info.gz"
      )
      Builtins.y2milestone(
        "compressed_packages_info: %1",
        compressed_packages_info
      )

      if !(Builtins.contains(@archivefiles, "info/files") &&
          (Builtins.contains(@archivefiles, "info/packages_info") ||
            Builtins.contains(@archivefiles, "info/packages_info.gz")) &&
          Builtins.contains(@archivefiles, "info/installed_packages"))
        # archive doesn't contain files from backup - file is not backup archive or not first volume of multi volume archive
        Builtins.y2error(
          "Archive does not contain 'info/files' or 'info/packages_info' or 'info/installed_packages' file!"
        )

        # error message
        Report.Error(
          _(
            "The archive does not contain the required files.\nIt was probably not created by the backup module.\n"
          )
        )
        return false
      end

      Builtins.y2debug("read archivefiles: %1", @archivefiles)

      infofiles = "info/comment info/hostname info/date info/installed_packages info/files info/complete_backup "

      infofiles = Ops.add(
        infofiles,
        compressed_packages_info ?
          "info/packages_info.gz" :
          "info/packages_info"
      )

      # unpack info files
      result = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add("/bin/tar -C '", String.Quote(@tempdir)),
                    "' -x -f '"
                  ),
                  String.Quote(@filename)
                ),
                "' "
              ),
              infofiles
            ),
            " 2> /dev/null"
          )
        )
      )

      @date = Convert.to_string(
        SCR.Read(path(".target.string"), Ops.add(@tempdir, "/info/date"))
      )
      @comment = Convert.to_string(
        SCR.Read(path(".target.string"), Ops.add(@tempdir, "/info/comment"))
      )
      @hostname = Convert.to_string(
        SCR.Read(path(".target.string"), Ops.add(@tempdir, "/info/hostname"))
      )

      complete_backup_str = Ops.greater_than(
        SCR.Read(
          path(".target.size"),
          Ops.add(@tempdir, "/info/complete_backup")
        ),
        0
      ) ?
        Convert.to_string(
          SCR.Read(
            path(".target.string"),
            Ops.add(@tempdir, "/info/complete_backup")
          )
        ) :
        ""

      Builtins.y2debug("complete_backup_str: %1", complete_backup_str)

      @complete_backup = Builtins.splitstring(complete_backup_str, "\n")
      Builtins.y2milestone("Complete backup: %1", @complete_backup)

      # read archive contents file
      archivefs = Convert.to_string(
        SCR.Read(path(".target.string"), Ops.add(@tempdir, "/info/files"))
      )

      if archivefs != nil
        @archivefiles = Builtins.splitstring(archivefs, "\n")
        @archivefiles = Builtins.filter(@archivefiles) do |pk|
          pk != "" && pk != nil
        end
      end

      Builtins.y2debug("final archivefiles: %1", @archivefiles)

      # read installed packages
      installedpkgs_str = Convert.to_string(
        SCR.Read(
          path(".target.string"),
          Ops.add(@tempdir, "/info/installed_packages")
        )
      )

      # convert string to list
      installedpkgs_list = Builtins.splitstring(installedpkgs_str, "\n")
      installedpkgs_list = Builtins.filter(installedpkgs_list) do |pk|
        pk != "" && pk != nil
      end

      # convert list to map (key - package name, value - package version)
      @installedpkgs = {}

      Builtins.foreach(installedpkgs_list) do |fullname|
        version = Builtins.regexpsub(fullname, ".*-(.*-.*)", "\\1")
        name = Builtins.substring(
          fullname,
          0,
          Ops.subtract(
            Ops.subtract(Builtins.size(fullname), Builtins.size(version)),
            1
          )
        )
        @installedpkgs = Builtins.add(@installedpkgs, name, version)
      end 


      if compressed_packages_info == true
        Builtins.y2milestone("Unpacking packages_info.gz file")
        # uncompress compressed package info
        SCR.Execute(
          path(".target.bash"),
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add("/usr/bin/gunzip -c ", @tempdir),
                "/info/packages_info.gz > "
              ),
              @tempdir
            ),
            "/info/packages_info"
          )
        )
        Builtins.y2milestone("File unpacked")
      end

      # covert package info file to YCP structure by perl script
      Builtins.y2milestone("Converting package info")
      SCR.Execute(
        path(".target.bash"),
        Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                "/usr/lib/YaST2/bin/restore_parse_pkginfo.pl < ",
                @tempdir
              ),
              "/info/packages_info > "
            ),
            @tempdir
          ),
          "/info.ycp"
        )
      )

      Builtins.y2milestone("Reading package info")
      @archive_info = Convert.convert(
        SCR.Read(path(".target.ycp"), Ops.add(@tempdir, "/info.ycp")),
        :from => "any",
        :to   => "map <string, map <string, any>>"
      )
      Builtins.y2milestone("Read %1 packages", Builtins.size(@archive_info))


      # read actual installed packages
      GetActualInstalledPackages()

      mismatched = GetMismatchedPackages()

      # add package descriptions and default selection
      @archive_info = Builtins.mapmap(@archive_info) do |p, i|
        # decription of files not owned by any package
        descr = p == "" ?
          _("Files not owned by any package") :
          Pkg.PkgSummary(p)
        i = {} if i == nil
        descr = "" if descr == nil
        t = Builtins.add(i, "descr", descr)
        sel_type = " "
        if Mode.config == false
          # set default selection to "X" (package is installed) or " " (package is not installed)
          if p == ""
            # set "no package" default value to "X"
            sel_type = "X"
          else
            sel_type = Builtins.haskey(@actualinstalledpackages, p) &&
              !Builtins.haskey(mismatched, p) ? "X" : " "
          end
        else
          # in autoinstall-config mode leave preselected value
          sel_type = Ops.get_string(i, "sel_type", " ")
        end
        t = Builtins.add(t, "sel_type", sel_type)
        { p => t }
      end

      if Mode.config == true
        # refresh file selection in autoinstall config mode
        Builtins.y2debug("Setting selection: %1", @autoinst_info)
        SetSelectionProperty(@autoinst_info)
      end

      Builtins.y2milestone(
        "values from archive: date=%1, comment=%2, hostname=%3",
        @date,
        @comment,
        @hostname
      )

      Builtins.y2debug("installed packages at backup time: %1", @installedpkgs)
      Builtins.y2debug(
        "actual installed packages: %1",
        GetActualInstalledPackages()
      )

      true
    end


    # Set settings
    # @param [Hash] settings Map with settings: start lilo, restore RPM db

    def Set(settings)
      settings = deep_copy(settings)
      Builtins.y2milestone("Using settings: %1", settings)
      @runbootloader = Ops.get_boolean(settings, "runbootloader", true)
      @restoreRPMdb = Ops.get_boolean(settings, "restoreRPMdb", false)
      @completerestoration = Ops.get_boolean(
        settings,
        "completerestoration",
        true
      )

      archiveslist = Ops.get_list(settings, "archives", [])
      @inputname = Ops.get(archiveslist, 0, "")
      # read archives
      if Builtins.size(archiveslist) == 0
        # set unconfigured state
        @inputname = ""
        @archive_info = {}
      end

      # set restore selection
      SetSelectionProperty(Ops.get_map(settings, "selection", {}))

      # store settings - file selection will be refreshed after archive selection
      # autoinstall config mode
      @autoinst_info = Ops.get_map(settings, "selection", {})
      Builtins.y2debug("setting autoinst_info: %1", @autoinst_info)

      Builtins.y2debug("archive_info: %1", @archive_info)

      nil
    end

    # Get all restore settings - for use by autoinstallation
    # @param [Hash] settings The YCP structure to be imported
    # @return [Boolean] True on success

    def Import(settings)
      settings = deep_copy(settings)
      return false if settings == nil

      Set(settings)

      true
    end


    # Dump the restore settings to a single map - for use by autoinstallation.
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      selection = {}

      if @inputname == ""
        # unconfigured
        return {}
      end

      Builtins.foreach(@archive_info) do |package, info|
        sel_type = Ops.get_string(info, "sel_type", " ")
        sel_file = Ops.get_list(info, "sel_file", [])
        package = @nopackage_id if package == ""
        selection = Builtins.add(
          selection,
          package,
          { "sel_type" => sel_type, "sel_file" => sel_file }
        )
      end 


      {
        "archives"            => Builtins.prepend(@inputvolumes, @inputname),
        "runbootloader"       => @runbootloader,
        "restoreRPMdb"        => @restoreRPMdb,
        "completerestoration" => @completerestoration,
        "selection"           => selection
      }
    end

    # Return restore configuration
    # @return [Hash] Map $[ "packagename" : $["vers" : "version", "files" : ["files in the archive"], "prefix" : "installprefix", "descr" : "Short description", "sel_type" : "X", "sel_file" : ["selected files to restore"] ] ], possible values for "sel_type" key are: "X" - restore all files from archive, " " - do not restore this package, "P" - partial restore, restore only selected files at "sel_file" key. Package name "" means files not owned by any package.
    def GetArchiveInfo
      deep_copy(@archive_info)
    end

    # Return number of packages which will be restored from archive
    # @return [Fixnum] Total selected packages
    def TotalPackagesToRestore
      total = 0

      # filter out unselected packages
      Builtins.foreach(@archive_info) do |p, info|
        sel_type = Ops.get_string(info, "sel_type", " ")
        total = Ops.add(total, 1) if sel_type == "X" || sel_type == "P"
      end 


      total
    end


    # Return number of files which will be unpacked from archive
    # @return [Fixnum] Total selected files
    def TotalFilesToRestore
      total = 0

      # filter out unselected packages and compute total restored files
      Builtins.foreach(@archive_info) do |p, info|
        sel_type = Ops.get_string(info, "sel_type", " ")
        if sel_type == "X"
          total = Ops.add(total, Builtins.size(Ops.get_list(info, "files", [])))
        elsif sel_type == "P"
          total = Ops.add(
            total,
            Builtins.size(Ops.get_list(info, "sel_file", []))
          )
        end
      end 


      total
    end

    # Activate boot loader configuration if requested.
    # Uses variable Restore::runbootloader
    # @return [Boolean] true on success
    def ActivateBootloader
      ret = nil

      # disable Bootloader's progress bar
      Progress.off

      if @runbootloader == true && Mode.test == false
        Builtins.y2milestone("activating boot loader configuration")

        # Bootloader function calls were moved to a client
        # to break the build-dependency on yast2-bootloader
        ret = Convert.to_boolean(WFM.call("restore_bootloader"))

        if ret == false
          # error popup message
          Report.Error(_("Boot loader configuration failed."))
        end

        Builtins.y2milestone("boot loader activated: %1", ret)
      end

      # re-enable progress bar
      Progress.on

      ret
    end

    # Restore files from archive
    # @param [Proc] abort This block is periodically evaluated, if it evaluates to true restoration will be aborted. It should be something like ``{return UI::PollInput () == `abort;} if UI exists or ``{ return false; } if there is no UI (abort will not be possible).
    # @param [Symbol] progress Id of progress bar or nil.
    # @param [String] targetdir Directory to which files from archive will be upacked
    # @return [Hash] Map $[ "aborted" : boolean, "restored" : [ "restored file" ], "failed" : [ "failed file" ] ]

    def Write(abort, progress, targetdir)
      abort = deep_copy(abort)
      restore = deep_copy(@archive_info)
      total = 0
      restoredpackages = 0
      restoredfiles = []
      failedfiles = []
      aborted = false

      if Builtins.size(targetdir) == 0 ||
          Builtins.substring(targetdir, 0, 1) != "/"
        # error message, %1 is directory
        Report.Error(
          Builtins.sformat(_("Invalid target directory (%1)."), targetdir)
        )
        return {
          "aborted"    => aborted,
          "restored"   => restoredfiles,
          "failed"     => failedfiles,
          "packages"   => restoredpackages,
          "bootloader" => false
        }
      end

      # create target directory if it doesn't exist
      out = Convert.to_integer(
        SCR.Execute(path(".target.bash"), Ops.add("/bin/mkdir -p ", targetdir))
      )
      if out != 0
        # error message
        Report.Error(Message.UnableToCreateDirectory(targetdir))
      end

      # filter out unselected packages and compute total restored files
      restore = Builtins.filter(restore) do |p, info|
        sel_type = Ops.get_string(info, "sel_type", " ")
        sel_type = "X" if @completerestoration
        if sel_type == "X"
          total = Ops.add(total, Builtins.size(Ops.get_list(info, "files", [])))
          next true
        elsif sel_type == "P"
          total = Ops.add(
            total,
            Builtins.size(Ops.get_list(info, "sel_file", []))
          )
          next true
        else
          next false
        end
      end

      Builtins.y2milestone("%1 files will be restored from archive", total)

      packages = []
      Builtins.foreach(restore) do |package, info|
        packages = Builtins.add(packages, package)
      end 


      i = 0
      ret = :next

      if @restoreRPMdb == true
        rpm_backup_script = "/etc/cron.daily/suse.de-backup-rpmdb"
        # backup existing RPM DB - use aaa_base script which is started from cron
        if Ops.greater_than(
            SCR.Read(path(".target.size"), rpm_backup_script),
            0
          )
          Builtins.y2milestone(
            "Startting RPM backup script (%1)",
            rpm_backup_script
          )
          result = Convert.to_integer(
            SCR.Execute(path(".target.bash"), rpm_backup_script)
          )
          Builtins.y2milestone("RPM backup exit value: %1", result)
        else
          Builtins.y2warning(
            "RPM DB backup script (%1) was not found, DB was not backed up!",
            rpm_backup_script
          )
        end

        stat = Ops.get_string(@archive_info, ["", "sel_type"], " ")
        Builtins.y2warning("NOPACKAGE status: '%1'", stat)
        Builtins.y2warning(
          "NOPACKAGE files: '%1'",
          Ops.get_list(@archive_info, ["", "files"], [])
        )

        if stat == " " || stat == "P"
          # RPM DB restoration is selected, but files not owned by any package are deselected
          # uncompress only RPM DB files, which are in directory /var/lib/rpm

          _RPM = []

          # search RPM DB files
          Builtins.foreach(Ops.get_list(@archive_info, ["", "files"], [])) do |f|
            if Builtins.regexpmatch(f, "^/var/lib/rpm/") == true
              _RPM = Builtins.add(_RPM, f)
            end
          end 


          Builtins.y2warning("found RPM DB files: %1", _RPM)

          if stat == " "
            _in = Builtins.eval(Ops.get(@archive_info, "", {}))

            Ops.set(_in, "sel_type", "P")
            Ops.set(_in, "sel_file", _RPM)

            # set new values
            Ops.set(restore, "", Builtins.eval(_in))

            total = Ops.add(total, Builtins.size(_RPM))
          else
            # may be some files are already selected
            # check status of each file
            already_selected = Ops.get_list(@archive_info, ["", "sel_file"], [])

            Builtins.foreach(_RPM) do |rpm_file|
              if !Builtins.contains(already_selected, rpm_file)
                already_selected = Builtins.add(already_selected, rpm_file)
                total = Ops.add(total, 1)
              end
            end 


            _in = Builtins.eval(Ops.get(@archive_info, "", {}))
            Ops.set(_in, "sel_file", already_selected)

            # set new values
            Ops.set(restore, "", Builtins.eval(_in))
          end
        end
      end

      Builtins.y2warning("packages: %1", packages)

      while Ops.less_than(i, Builtins.size(packages))
        package = Ops.get(packages, i, "nonexistingpackage")
        info = Ops.get(restore, package, {})
        # progress bar label
        label = package == "" ?
          _("Restoring files not owned by any package...") :
          # progress bar label - %1 is package name
          Builtins.sformat(_("Restoring package %1..."), package)
        sel_type = Ops.get_string(info, "sel_type", "")

        if progress != nil
          # update name of package
          UI.ChangeWidget(Id(progress), :Label, label)
          UI.ChangeWidget(Id(progress), :Value, i)
        end

        if Mode.test == true
          # delay
          Builtins.sleep(300)
        else
          # y2logs will be probably overwritten - backup them
          if package == "" && @targetDirectory == "/"
            copy = Convert.to_integer(
              SCR.Execute(
                path(".target.bash"),
                "cp -r /var/log/YaST2 /var/log/YaST2.before_restore"
              )
            )
            Builtins.y2milestone(
              "copy y2logs to /var/log/YaST2.before_restore: ret=%1",
              copy
            )
          end

          # get subarchive name
          name = package == "" ?
            "NOPACKAGE" :
            Ops.add(Ops.add(package, "-"), Ops.get_string(info, "vers", ""))
          fileinarchive = ""

          Builtins.foreach(@archivefiles) do |f|
            if Builtins.regexpmatch(
                f,
                Ops.add(Ops.add("^", name), "-........-.\\.s{0,1}tar.*")
              ) == true
              Builtins.y2debug("package %1 is in archive file %2", package, f)
              fileinarchive = f
            end
          end 


          # BNC #460674, Do not change the system locale
          # It can change I18N characters in output
          locale_modifications = ""

          if fileinarchive == ""
            Builtins.y2error("Can't find subarchive for package %1", package)
          else
            # unpack subarchive at background
            started = nil

            if IsMultiVolume() == true
              param = " "

              Builtins.foreach(@volumeparts) do |f|
                param = Ops.add(
                  Ops.add(Ops.add(param, "-f '"), String.Quote(f)),
                  "' "
                )
              end 


              command = Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(
                        Ops.add(
                          Ops.add(locale_modifications, "echo q | /bin/tar -C "),
                          @tempdir
                        ),
                        " -x -M "
                      ),
                      param
                    ),
                    "'"
                  ),
                  String.Quote(fileinarchive)
                ),
                "' 2> /dev/null"
              )
              Builtins.y2milestone("Running command: %1", command)

              started = Convert.to_boolean(
                SCR.Execute(path(".background.run"), command)
              )
            else
              command = Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(
                        Ops.add(
                          Ops.add(locale_modifications, "/bin/tar -C "),
                          @tempdir
                        ),
                        " -x -f '"
                      ),
                      String.Quote(@filename)
                    ),
                    "' '"
                  ),
                  String.Quote(fileinarchive)
                ),
                "'"
              )
              Builtins.y2milestone("Running command: %1", command)

              started = Convert.to_boolean(
                SCR.Execute(path(".background.run"), command)
              )
            end

            # abort test cycle
            while Convert.to_boolean(SCR.Read(path(".background.isrunning")))
              Builtins.sleep(100)

              aborted = Builtins.eval(abort)

              if aborted == true
                Builtins.y2warning("Restoration aborted!")
                SCR.Execute(path(".background.kill"), nil) # kill subprocess
                break
              end
            end

            # break all packages cycle
            break if aborted == true

            # set compression parameter
            compress = ""

            # use star archiver
            star = false

            if Builtins.regexpmatch(fileinarchive, ".*\\.tar\\.gz$") == true
              compress = "-z"
            elsif Builtins.regexpmatch(fileinarchive, ".*\\.tar\\.bz2$") == true
              compress = "-j"
            elsif Builtins.regexpmatch(fileinarchive, ".*\\.star$") ||
                Builtins.regexpmatch(fileinarchive, ".*\\.star\\.gz$") ||
                Builtins.regexpmatch(fileinarchive, ".*\\.star\\.bz2$") == true
              # star can autodetect used compression
              compress = ""
              star = true
            end

            Builtins.y2debug("compress: %1", compress)
            Builtins.y2debug("star: %1", star)
            Builtins.y2debug("fileinarchive: %1", fileinarchive)

            _RPMdb = @restoreRPMdb ?
              "" :
              star ? "-not pat=var/lib/rpm" : "--exclude var/lib/rpm"

            # files to unpack, "" means all files
            unpackfiles = ""

            # select files to unpack
            if sel_type == "P"
              # strip leading '/'
              Builtins.foreach(Ops.get_list(info, "sel_file", [])) do |f|
                if Ops.greater_than(Builtins.size(f), 1)
                  # remove a leading slash
                  if Builtins.substring(f, 0, 1) == "/"
                    f = Builtins.substring(f, 1)
                  end
                  # every single entry must be quoted
                  unpackfiles = Ops.add(
                    Ops.add(Ops.add(unpackfiles, " '"), String.Quote(f)),
                    "'"
                  )
                end
              end
            end

            # FIXME: use list of files
            # for star: list=filename
            # for tar:  --files-from=filename

            # create (s)tar command
            tarcommand = star == false ?
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
                                  Ops.add(
                                    Ops.add(
                                      Ops.add(
                                        Ops.add(
                                          Ops.add(
                                            Ops.add(
                                              Ops.add(
                                                locale_modifications,
                                                "/bin/tar -C "
                                              ),
                                              targetdir
                                            ),
                                            " "
                                          ),
                                          compress
                                        ),
                                        " -x -v -f "
                                      ),
                                      @tempdir
                                    ),
                                    "/"
                                  ),
                                  fileinarchive
                                ),
                                " "
                              ),
                              _RPMdb
                            ),
                            " "
                          ),
                          unpackfiles
                        ),
                        " 2> "
                      ),
                      @tempdir
                    ),
                    "/tar.stderr > "
                  ),
                  @tempdir
                ),
                "/tar.stdout"
              ) :
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
                                  Ops.add(
                                    Ops.add(
                                      Ops.add(
                                        Ops.add(
                                          Ops.add(
                                            Ops.add(
                                              Ops.add(
                                                locale_modifications,
                                                "/usr/bin/star -C "
                                              ),
                                              targetdir
                                            ),
                                            " "
                                          ),
                                          compress
                                        ),
                                        " -x -v -U -f "
                                      ),
                                      @tempdir
                                    ),
                                    "/"
                                  ),
                                  fileinarchive
                                ),
                                " "
                              ),
                              _RPMdb
                            ),
                            " "
                          ),
                          unpackfiles
                        ),
                        " 2> "
                      ),
                      @tempdir
                    ),
                    "/tar.stderr > "
                  ),
                  @tempdir
                ),
                "/tar.stdout"
              )
            # -U option: replace existing files

            Builtins.y2milestone("tarcommand: %1", tarcommand)

            # check whether star is installed
            if Ops.less_than(SCR.Read(path(".target.size"), "/usr/bin/star"), 0) &&
                star == true
              # remove short
              cont = Label.ContinueButton
              cont = Builtins.mergestring(Builtins.splitstring(cont, "&"), "")

              # popup message text - ask to install 'star' package
              # %1 is translated 'Continue' label
              inst = Popup.ContinueCancel(
                Builtins.sformat(
                  _(
                    "Package star is needed to extract\n" +
                      "files from the archive.\n" +
                      "Press %1 to install this package.\n"
                  ),
                  cont
                )
              )

              if inst == true
                # install star package

                # initialize package manager
                Pkg.SourceStartCache(true)
                Pkg.TargetInit("/", false)

                ok = true

                # select star package to installation
                ok = Pkg.PkgInstall("star")

                # solve dependencies
                ok = ok && Pkg.PkgSolve(false)

                # perform installation (0 means install from all media)
                result = Pkg.PkgCommit(0)

                # check result
                Builtins.y2debug("PkgCommit: %1", result)
                inst = ok && Ops.get(result, 1) == [] &&
                  Ops.get(result, 2) == []
              end

              # abort restoration if star installation failed
              if inst == false
                # error popup message
                Report.Error(
                  _("Package star is not installed.\nPress OK to exit.\n")
                )
                Builtins.y2error("star package wasn't installed - aborting")

                return {
                  "aborted"    => true,
                  "restored"   => restoredfiles,
                  "failed"     => failedfiles,
                  "packages"   => restoredpackages,
                  "bootloader" => false
                }
              end
            end

            # start subprocess
            started = Convert.to_boolean(
              SCR.Execute(path(".background.run_output"), tarcommand)
            )

            Builtins.y2milestone("Tar command started: %1", started)

            while SCR.Read(path(".background.isrunning")) == true
              Builtins.sleep(100) # small delay

              aborted = Builtins.eval(abort)

              if aborted == true
                Builtins.y2warning("Restoration aborted!")
                SCR.Execute(path(".background.kill"), nil) # kill subprocess
                break
              end
            end

            # read restored files
            stdout = Builtins.splitstring(
              Convert.to_string(
                SCR.Read(
                  path(".target.string"),
                  Ops.add(@tempdir, "/tar.stdout")
                )
              ),
              "\n"
            )

            # remove empty lines
            stdout = Builtins.filter(stdout) do |line|
              Ops.greater_than(Builtins.size(line), 0)
            end if stdout != nil

            # star has more verbose output - get only file names
            if star && stdout != nil
              filteredstdout = []
              Builtins.foreach(stdout) do |line|
                new = Builtins.regexpsub(
                  line,
                  "x (.*) .* bytes, .* tape blocks",
                  "\\1"
                )
                filteredstdout = Builtins.add(filteredstdout, new) if new != nil
              end 


              stdout = deep_copy(filteredstdout)
            end

            Builtins.y2debug("stdout: %1", stdout)

            if stdout != nil
              restoredfiles = Convert.convert(
                Builtins.merge(restoredfiles, stdout),
                :from => "list",
                :to   => "list <string>"
              )
            end

            # read failed files
            stderr = Builtins.splitstring(
              Convert.to_string(
                SCR.Read(
                  path(".target.string"),
                  Ops.add(@tempdir, "/tar.stderr")
                )
              ),
              "\n"
            )

            # remove empty lines
            stderr = Builtins.filter(stderr) do |line|
              Ops.greater_than(Builtins.size(line), 0)
            end
            packagefailedfiles = 0

            Builtins.y2warning("stderr: %1", stderr) if stderr != []

            # add file names to failedfiles
            Builtins.foreach(stderr) do |line|
              Builtins.y2warning("line: %1", line)
              if line != nil && line != ""
                file = Builtins.regexpsub(line, "s{0,1}tar: (.*)", "\\1")

                # ignore final star summary
                if file != nil &&
                    !Builtins.regexpmatch(
                      line,
                      "star: .* blocks \\+ .* bytes \\(total of .* bytes = .*k\\)\\."
                    ) &&
                    !Builtins.regexpmatch(line, "star: WARNING: .*")
                  failedfiles = Builtins.add(failedfiles, file)
                  packagefailedfiles = Ops.add(packagefailedfiles, 1)

                  Builtins.y2warning("Restoration of file %1 failed", file)
                end
              end
            end 


            # package restoration failed
            if restoredfiles != nil &&
                packagefailedfiles == Builtins.size(restoredfiles)
              Builtins.y2warning("failed package: %1", package)
            else
              restoredpackages = Ops.add(restoredpackages, 1)
            end

            break if aborted == true
          end
        end

        i = Ops.add(i, 1)
      end

      # sort list of restored files and remove duplicates (caused by multiple unpacking)
      restoredfiles = Builtins.toset(restoredfiles)

      # remove failed files
      restoredfiles = Builtins.filter(restoredfiles) do |f|
        !Builtins.contains(failedfiles, f)
      end

      if @runbootloader == true && progress != nil
        # progess bar label
        UI.ChangeWidget(Id(progress), :Label, _("Configuring boot loader..."))
        UI.ChangeWidget(Id(progress), :Value, i)
      end

      bootload = ActivateBootloader()

      {
        "aborted"    => aborted,
        "restored"   => restoredfiles,
        "failed"     => failedfiles,
        "packages"   => restoredpackages,
        "bootloader" => bootload
      }
    end

    # Read next volume of multi volume archive
    # @param [String] input Archive name in URL-like syntax
    # @return [Hash] Map $[ "success" : boolean (true on success), "lastvolume" : boolean (true if archive is last volume) ]

    def ReadNextVolume(input)
      # umount mounted file system
      Umount()

      ret = false
      last = true

      # mount source
      mount = MountInput(input)

      if Ops.get_boolean(mount, "success", false) == true
        @mountpoint = Ops.get_string(mount, "mpoint", "")

        # add mounted file
        addvol = AddVolume(Ops.get_string(mount, "file", "dummy"))

        ret = Ops.get_boolean(addvol, "success", false)
        last = Ops.get_boolean(addvol, "lastvolume", true)

        @inputvolumes = Builtins.add(@inputvolumes, input) if ret == true
      end

      { "success" => ret, "lastvolume" => last }
    end


    # Test all volumes together
    # @return [Boolean] True: all volumes are OK, false: an error occured

    def TestAllVolumes
      ret = false

      if Ops.greater_than(Builtins.size(@volumeparts), 0)
        param = ""

        Builtins.foreach(@volumeparts) do |f|
          param = Ops.add(Ops.add(Ops.add(param, "-f "), f), " ")
        end 


        # echo 'q' to tar stdin - if error occurs tar asks for next volume, q means quit
        exit = Convert.to_integer(
          SCR.Execute(
            path(".target.bash"),
            Ops.add("echo q | /bin/tar -t -M ", param)
          )
        )
        Builtins.y2milestone("Test result: %1", exit)

        ret = exit == 0
      end

      ret
    end

    # Clear all archive settings

    def ResetArchiveSelection
      # clear selected archive
      @filename = ""
      @inputname = ""

      # clear content of archive
      @archivefiles = []

      # clear installed packages at backup time
      @installedpkgs = {}

      # clear archive selection
      @archive_info = {}

      # clear archive info
      @date = ""
      @hostname = ""
      @comment = ""

      # clear list of files
      @volumeparts = []

      Umount()

      nil
    end


    # Clear all settings (archive and list of installed packages)

    def ResetAll
      ResetArchiveSelection()

      # clear list of installed packages
      @actualinstalledpackages = {}

      nil
    end

    # Remove shortcut mark from string
    # @param [String] scut string with shortcut mark (&)
    # @return [String] result
    def RemoveShortCut(scut)
      Builtins.mergestring(Builtins.splitstring(scut, "&"), "")
    end

    # Convert boolean value to translated "yes" or "no" string
    # @param [Boolean] b input value
    # @return [String] translated Yes/No string
    def yesno(b)
      ret = "?"

      ret = _("Yes") if b == true
      ret = _("No") if b == false

      ret
    end

    # Create restore configuration summary. Used in autoinstallation restore module configuration.
    # @return [String] rich text summary

    def Summary
      if @inputname == ""
        # not configured yet
        return Summary.NotConfigured
      else
        # Summary text header
        archives_info = "<P><B>" + _("Backup Archive") + "<B></P>"

        archives_info = Ops.add(Ops.add(archives_info, "<P>"), @inputname)
        Builtins.foreach(@inputvolumes) do |vol|
          archives_info = Ops.add(Ops.add(archives_info, vol), "<BR>")
        end 

        archives_info = Ops.add(archives_info, "</P>")

        # Summary text header
        options_info = "<P><B>" + _("Restore Options") + "<B></P>"

        options_info = Ops.add(
          Ops.add(
            Ops.add(
              Ops.add(
                Ops.add(
                  Ops.add(
                    Ops.add(
                      Ops.add(
                        Ops.add(options_info, "<P>"),
                        RemoveShortCut(
                          _(
                            "Activate &boot loader configuration after restoration"
                          )
                        )
                      ),
                      ":  "
                    ),
                    yesno(@runbootloader)
                  ),
                  "<BR>"
                ),
                RemoveShortCut(
                  _("Restore RPM &database (if present in archive)")
                )
              ),
              ":  "
            ),
            yesno(@restoreRPMdb)
          ),
          "<BR></P>"
        )

        # summary text heading
        selection_info = "<P><B>" + _("Packages to Restore") + "</B></P><P>"

        if @completerestoration
          # part of the summary text
          selection_info = Ops.add(
            selection_info,
            _("<I>Restore all files from the archive</I>")
          )
        elsif @archive_info != nil
          Builtins.foreach(@archive_info) do |p, info|
            p = _("--No package--") if p == ""
            if Ops.get_string(info, "sel_type", " ") != " "
              selection_info = Ops.add(Ops.add(selection_info, p), "<BR>")
            end
          end
        end

        selection_info = Ops.add(selection_info, "</P>")

        return Ops.add(Ops.add(archives_info, options_info), selection_info)
      end
    end


    def ProposeRPMdbRestoration
      extra = GetExtraPackages()
      missing = GetMissingPackages()
      mismatched = GetMismatchedPackages()

      selected = GetSelectedPackages()

      # proposed DB restoration
      propose = nil

      Builtins.y2debug("extra: %1, missig: %2", extra, missing)

      selected_list = []
      Builtins.foreach(selected) do |p, _in|
        # store package name and vesion to the list
        selected_list = Builtins.add(
          selected_list,
          Ops.add(Ops.add(p, "-"), Ops.get_string(_in, "vers", ""))
        )
      end 


      Builtins.y2debug("selected_list: %1", selected_list)

      # propose restoration when:
      # - missing packages contain only fully backed packages
      # - all fully backed packages will be restored
      # - there is no extra package
      if Builtins.size(extra) == 0
        all = true
        Builtins.y2debug("size(extra): %1", Builtins.size(extra))

        Builtins.foreach(@complete_backup) do |fullpkg|
          #		    integer pos = findlastof(fullpkg, "-");
          #		    string basename = substring(fullpkg, pos);
          #		    string version = substring(fullpkg, 0, pos);
          all = false if !Builtins.contains(selected_list, fullpkg)
        end 


        Builtins.y2debug("all completely packages selected: %1", all)

        if all == true
          # check missing packages - it should contain only completely backed up packages
          Builtins.foreach(missing) do |pkg, inf|
            fpkg = Ops.add(Ops.add(pkg, "-"), Ops.get_string(inf, "vers", ""))
            all = false if !Builtins.contains(@complete_backup, fpkg)
          end 


          if all == true
            Builtins.y2debug("only fully backed up packages are missing")
            # RPM DB restoration is recommended
            return { "proposed" => true }
          end
        end
      end

      ok = true
      # propose no restoration if only installed packages will be restored
      Builtins.foreach(selected) do |pk, inf|
        version = Ops.get_string(inf, "vers", "")
        # selected packages are not missing
        if ok && (Ops.get(missing, pk) != nil || Ops.get(mismatched, pk) != nil)
          ok = false
        end
      end 


      return { "proposed" => false } if ok == true

      # there will be inconsistency between RPM DB and system,
      # some packages will be in DB but no files will be present
      # or there will be files without RPM entry or both
      # it is also possible that package versions do not match

      different_versions = {} # package in system => package in RPM in the archive
      not_in_system = [] # package is in DB in the archive, but not in the system and it won't be restored
      not_in_archiveDB = [] # not in the archive, but in the system

      Builtins.foreach(mismatched) do |p, inf|
        if Ops.get(selected, p) != nil
          #                    different_versions[p + "-" + selected["vers"]:""] = p + "-" + inf["inst"]:"";
          Ops.set(
            different_versions,
            p,
            Ops.add(Ops.add(p, "-"), Ops.get(inf, "inst", ""))
          )
        end
      end 


      Builtins.foreach(missing) do |p, inf|
        not_in_system = Builtins.add(
          not_in_system,
          Ops.add(Ops.add(p, "-"), Ops.get_string(inf, "vers", ""))
        )
      end 


      Builtins.foreach(extra) do |p, inf|
        not_in_archiveDB = Builtins.add(
          not_in_archiveDB,
          Ops.add(Ops.add(p, "-"), Ops.get_string(inf, "vers", ""))
        )
      end 


      # both possible operations (restoration or preserving RPM DB)
      # will cause to inconsistency in system
      {
        "proposed"   => nil,
        "mismatched" => different_versions,
        "missing"    => missing,
        "extra"      => extra
      }
    end


    def RPMrestorable
      nopkgfiles = Ops.get_list(@archive_info, ["", "files"], [])
      Builtins.contains(nopkgfiles, "/var/lib/rpm/Packages")
    end

    publish :variable => :inputname, :type => "string"
    publish :variable => :completerestoration, :type => "boolean"
    publish :variable => :targetDirectory, :type => "string"
    publish :variable => :runbootloader, :type => "boolean"
    publish :variable => :restoreRPMdb, :type => "boolean"
    publish :function => :Modified, :type => "boolean ()"
    publish :function => :SetModified, :type => "void ()"
    publish :function => :IsMultiVolume, :type => "boolean ()"
    publish :function => :GetArchiveDate, :type => "string ()"
    publish :function => :GetInputName, :type => "string ()"
    publish :function => :GetArchiveName, :type => "string ()"
    publish :function => :GetArchiveComment, :type => "string ()"
    publish :function => :GetArchiveHostname, :type => "string ()"
    publish :function => :GetArchiveInstalledPackages, :type => "map <string, string> ()"
    publish :function => :GetArchiveFiles, :type => "list ()"
    publish :function => :ReadActualInstalledPackages, :type => "map <string, string> ()"
    publish :function => :GetActualInstalledPackages, :type => "map <string, string> ()"
    publish :function => :GetMissingPackages, :type => "map <string, map <string, string>> ()"
    publish :function => :GetExtraPackages, :type => "map <string, map <string, string>> ()"
    publish :function => :GetMismatchedPackages, :type => "map <string, map <string, string>> ()"
    publish :function => :GetSelectedPackages, :type => "map <string, map> ()"
    publish :function => :ClearInstalledPackagesCache, :type => "void ()"
    publish :function => :Umount, :type => "void ()"
    publish :function => :MountInput, :type => "map (string)"
    publish :function => :SetRestoreSelection, :type => "void (string, map)"
    publish :function => :SetSelectionProperty, :type => "void (map <string, map>)"
    publish :function => :Read, :type => "boolean (string)"
    publish :function => :Set, :type => "void (map)"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :GetArchiveInfo, :type => "map <string, map <string, any>> ()"
    publish :function => :TotalPackagesToRestore, :type => "integer ()"
    publish :function => :TotalFilesToRestore, :type => "integer ()"
    publish :function => :ActivateBootloader, :type => "boolean ()"
    publish :function => :Write, :type => "map (block <boolean>, symbol, string)"
    publish :function => :ReadNextVolume, :type => "map (string)"
    publish :function => :TestAllVolumes, :type => "boolean ()"
    publish :function => :ResetArchiveSelection, :type => "void ()"
    publish :function => :ResetAll, :type => "void ()"
    publish :function => :Summary, :type => "string ()"
    publish :function => :ProposeRPMdbRestoration, :type => "map <string, any> ()"
    publish :function => :RPMrestorable, :type => "boolean ()"
  end

  Restore = RestoreClass.new
  Restore.main
end
