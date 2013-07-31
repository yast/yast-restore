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
#   include/restore/helps.ycp
#
# Package:
#   Restore module
#
# Summary:
#   Help texts of all the dialogs.
#
# Authors:
#   Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
# The help texts.
#
module Yast
  module RestoreHelpsInclude
    def initialize_restore_helps(include_target)
      textdomain "restore"
    end

    # Help text for archive selection dialog
    # @return [String] Help text

    def ArchiveSelectionHelp
      # For translators: archive selection dialog help (part 1)
      _(
        "<P><B><BIG>Restore Module</BIG></B><BR>The restore module can restore your system from a backup archive.</P>"
      ) +
        # For translators: archive selection dialog help, (part 2)
        _("<P>Archive can be read from:</P>") +
        # For translators: archive selection dialog help, (part 3)
        _(
          "<P><B>Local File</B>: The archive is already available in the system. It is on a mounted file system.</P>"
        ) +
        # For translators: archive selection dialog help, (part 4)
        _(
          "<P><B>Network</B>: The backup archive can be read from network using NFS.</P>"
        ) +
        # For translators: archive selection dialog help, (part 5)
        _(
          "<P><B>Removable Device</B>: The archive is on a removable device or\n" +
            "on an unmounted file system. The device can be selected from a list or you can enter the device filename\n" +
            "(for example, /dev/hdc) if not listed.</P>\n"
        ) +
        # For translators: archive selection dialog help, (part 6)
        _(
          "<P>If you press <B>Select</B>, the device is mounted\nand you can select the file from a dialog.</P>\n"
        ) +
        # For translators: archive selection dialog help (part 7)
        _(
          "<P>Note: If you have a multivolume archive, select the first volume.</P>"
        )
    end


    # Help text for multivolume archive dialog
    # @return [String] Help text

    def ArchiveMultiSelectionHelp
      # multi volume archive selection help text 1/2
      _(
        "<P><B><BIG>Multivolume Archive</BIG></B><BR>The backup archive has more than\none volume.  In this dialog, enter volumes that belong to the backup archive.</P>\n"
      ) +
        # multi volume archive selection help text 2/2
        _(
          "<P>After the volume is read, the filename is automatically changed to the\n" +
            "next volume name. Press <B>Next</B> to\n" +
            "continue to the next volume.</P>\n"
        )
    end


    # Help text for archive property dialog
    # @return [String] Help text

    def ArchivePropertyHelp
      # For translators: archive property dialog help
      _(
        "<P><B><BIG>Archive Properties</BIG></B><BR>Information about the backup archive\n" +
          "is displayed here.  Press <B>Archive Contents</B> to\n" +
          "show the contents of the archive.  Press <B>Expert Options</B> to set advanced restore\n" +
          "options.  If the archive is a multivolume archive, \n" +
          "select more volumes after pressing <B>Next</B>.</P>"
      )
    end


    # Help text for archive content dialog
    # @return [String] Help text

    def ArchiveContentHelp
      # For translators: archive property dialog help
      _(
        "<P><B><BIG>Archive Contents</BIG></B><BR>\nThe packages and files in the backup archive are displayed here.</P>\n"
      )
    end


    # Help text for options dialog
    # @return [String] Help text

    def RestoreOptionsHelp
      # For translators: option dialog help (part 1)
      _(
        "<P><B><BIG>Restore Options</BIG></B><BR>These options are intended for\nexpert users. The default values are usually appropriate.</P>\n"
      ) +
        # For translators: option dialog help (part 2)
        _(
          "<p>Select <B>Activate Boot Loader Configuration</B> to reinstall the boot loader.\nSome boot loaders, such as LILO, must be reinstalled if configuration files or files needed at system boot are changed.</p>\n"
        )
    end


    # Part of help text, it is used at more help texts
    # @return [String] Help text

    def RestorePackageHelp
      # For translators: package restoration note (used in more dialogs)
      _(
        "<P><B><BIG>Package Restoration</BIG></B><BR>Restore the set of installed packages to the state at the time of backup.</P>"
      )
    end


    # Help text for install package selection dialog
    # @return [String] Help text

    def InstallPackageHelp
      Ops.add(
        RestorePackageHelp(),
        # For translators: package installation help
        _(
          "<P>There is a list with uninstalled packages in the table. These packages\n" +
            "were installed at backup time, but are now missing.  To obtain the same system \n" +
            "configuration as at the time of backup, select all packages.  <b>X</b> in \n" +
            "the first column means that the package will be installed.</P>"
        )
      )
    end


    # Help text for uninstall package selection dialog
    # @return [String] Help text

    def UninstallPackageHelp
      Ops.add(
        Ops.add(
          RestorePackageHelp(),
          # For translators: package uninstallation help
          _(
            "<P>Packages in the table were not installed at the time of backup, but are now.  To obtain the same system configuration as at backup time, uninstall all packages. </P>"
          )
        ),
        # For translators: package uninstallation help (part 2)
        _(
          "<P><b>X</b> in the first column means that the package will be \nuninstalled. To leave a package installed, deselect it.</P>"
        )
      )
    end


    # Help text for package selection dialog
    # @param [Boolean] personal If false, add partial selection help text
    # @return [String] Help text

    def RestoreSelectionHelp(personal)
      # For translators: restore selection help 1/5
      _(
        "<P><B><BIG>Selection</BIG></B><BR>\nSelect which packages to restore from the backup archive.</P>\n"
      ) +
        # For translators: restore selection help 2/5
        _(
          "<P>The first column displays the restoration status of the package. It can be <b>X</b> (package will be restored) or empty (package will not be restored).</P>"
        ) +
        # For translators: restore selection help 3/5
        (personal == false ?
          _(
            "<P><b>P</b> means that a package will be restored only partially. Press <B>Select Files</B> to restore a package partially.</P>"
          ) :
          "") +
        # For translators: restore selection help 4/5
        _(
          "<P>The number of selected files to restore from the archive is in the second column.</P>"
        ) +
        # For translators: restore selection help 5/5
        _(
          "<p>If you deleted the RPM database by mistake or if it is badly\n" +
            "corrupted, select <b>Restore RPM Database</b>.\n" +
            "The database is then restored if it is available in the backup archive.\n" +
            "In other cases, leave this option unchecked.</p>"
        )
    end


    # Help text for file selection dialog
    # @return [String] Help text

    def FileSelectionHelp
      # For translators: file selection help (part 1)
      _(
        "<P><B><BIG>File Selection</BIG></B><BR>\n" +
          "Select which files to restore.\n" +
          "</P>\n"
      )
    end


    # Help text for progress dialog
    # @return [String] Help text

    def RestoreProgressHelp
      # progress bar help text
      _(
        "<P><B><BIG>Restoring</BIG></B><BR>\n" +
          "Files are being restored from the backup archive now.\n" +
          "It will take some time, depending on the size and number of restored files.\n" +
          "</P>\n"
      )
    end


    # Help text for summary dialog
    # @return [String] Help text

    def SummaryHelp
      # summary dialog help text 1/3
      _(
        "<P><B><BIG>Summary</BIG></B><BR>\n" +
          "This is a summary of the restoration process. To see more details, select\n" +
          "<B>Show Details</B>. To save the summary to a file, select <B>Save to File</B>.\n" +
          "</P>\n" +
          "\n"
      ) +
        # summary dialog help text 2/3
        _(
          "<P><B>Note:</B> Displaying the detailed summary can \n" +
            "take a long time depending on the number\n" +
            "of restored files.\n" +
            "</P>\n"
        ) +
        # summary dialog help text 3/3
        _(
          "<P>Some changes, such as a kernel update, made by the restore \n" +
            "module can be activated only after a system\n" +
            "reboot. It is recommended to reboot the system after\n" +
            "restoration.</P>\n"
        )
    end
  end
end
