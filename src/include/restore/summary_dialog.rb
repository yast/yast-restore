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
#   include/restore/summary_dialog.ycp
#
# Package:
#   Restore module
#
# Summary:
#   Display summary dialog.
#
# Authors:
#   Ladislav Slezak <lslezak@suse.cz>
#
# $Id$
#
# Display summary dialog in wizard with optional details. Summary can be saved to file.
#
module Yast
  module RestoreSummaryDialogInclude
    def initialize_restore_summary_dialog(include_target)
      Yast.import "UI"

      textdomain "restore"

      Yast.import "Wizard"

      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "Directory"
      Yast.import "String"
    end

    # This function removes HTML tags from input string
    # @param input Input string
    # @return [String] String without tags

    def RemoveTags(ret)
      tagmapping = {
        "BR"      => "\n",
        "/P"      => "\n",
        "P"       => "",
        "B"       => "",
        "/B"      => "",
        "EM"      => "",
        "/EM"     => "",
        "I"       => "",
        "/I"      => "",
        "TT"      => "",
        "/TT"     => "",
        "/BIG"    => "",
        "BIG"     => "",
        "CODE"    => "/CODE",
        "STRONG"  => "",
        "/STRONG" => "",
        "PRE"     => "",
        "/PRE"    => "",
        "LARGE"   => "",
        "/LARGE"  => "",
        "HR"      => "",
        "H1"      => "",
        "/H1"     => "",
        "H2"      => "",
        "/H2"     => "",
        "H3"      => "",
        "/H3"     => ""
      }

      tag = nil
      taglower = nil

      Builtins.foreach(tagmapping) do |t, repl|
        tag = Ops.add(Ops.add("<", t), ">")
        while Builtins.issubstring(ret.value, tag)
          ret.value = Builtins.regexpsub(
            ret.value,
            Ops.add(Ops.add("(.*)", tag), "(.*)"),
            Ops.add(Ops.add("\\1", repl), "\\2")
          )
        end
        taglower = Builtins.tolower(tag)
        while Builtins.issubstring(ret.value, taglower)
          ret.value = Builtins.regexpsub(
            ret.value,
            Ops.add(Ops.add("(.*)", taglower), "(.*)"),
            Ops.add(Ops.add("\\1", repl), "\\2")
          )
        end
      end 


      ret.value
    end

    # Display summary dialog with optional details, it is possible to save dialog contents to file
    # @param [String] text Summary text
    # @param [String] detail_text Detailed summary text
    # @param [String] helptext Help text for wizard
    # @param [String] label Text in label
    # @param [Symbol] button Label for `next button, possible values are `next (label is "Next"), `ok ("Ok") or `finish ("Finish")
    # @return [Symbol] Id of pressed button (`next, `back, `abort)

    def DisplaySummaryDialog(text, detail_text, helptext, label, button)
      contents = VBox(
        VSpacing(0.5),
        RichText(Id(:rt), text),
        VSpacing(0.5),
        # push button label
        HBox(
          CheckBox(
            Id(:details),
            Opt(:notify, :key_F2),
            _("&Show Details"),
            false
          ),
          HSpacing(3),
          # push button label
          PushButton(Id(:save), _("Sa&ve to File..."))
        ),
        VSpacing(1.0)
      )

      if button == :finish
        Wizard.SetNextButton(:next, Label.FinishButton)
      elsif button == :ok
        Wizard.SetNextButton(:next, Label.OKButton)
      elsif button == :next
        Wizard.RestoreNextButton
      else
        Builtins.y2warning("Unknown button: %1", button)
      end

      Wizard.SetContents(label, contents, helptext, true, true)

      ret = nil
      begin
        ret = UI.UserInput

        details = Convert.to_boolean(UI.QueryWidget(Id(:details), :Value))

        if ret == :details
          UI.ChangeWidget(Id(:rt), :Value, details == true ? detail_text : text)
        elsif ret == :save
          savefile = UI.AskForSaveFileName("/", "*", _("Save Summary to File"))

          if savefile != "" && savefile != nil
            # Create or empty the file
            SCR.Write(path(".target.string"), savefile, "")

            # BNC #460674
            # Due to the very ineffective all-in-one-run function, removing HTML
            # and writing thw whole file at once takes just too much time
            #
            # Fixed by going through the summary line by line (by <BR>s)

            tmpfile = Ops.add(Directory.tmpdir, "/restore_tmpfile")

            Builtins.y2milestone("Using tmpfile: %1", tmpfile)
            # Using tmpfile - there are more powerful tools for parsing text
            if SCR.Write(path(".target.string"), tmpfile, detail_text)
              if Convert.to_integer(
                  SCR.Execute(
                    path(".target.bash"),
                    Builtins.sformat(
                      "perl -pi -e \"s/<BR>/\\n/g;\" '%1'",
                      String.Quote(tmpfile)
                    )
                  )
                ) == 0
                detail_text = Convert.to_string(
                  SCR.Read(path(".target.string"), tmpfile)
                )
              end
            end

            Builtins.foreach(Builtins.splitstring(detail_text, "\n")) do |one_line|
              # <BR> == newline
              one_line = Ops.add(one_line, "\n")
              # Appending lines one by one
              SCR.Write(
                path(".backup.file_append"),
                [
                  savefile,
                  (
                    one_line_ref = arg_ref(one_line);
                    _RemoveTags_result = RemoveTags(one_line_ref);
                    one_line = one_line_ref.value;
                    _RemoveTags_result
                  )
                ]
              )
            end

            Builtins.y2milestone("Summary saved to file: %1", savefile)
          end
        elsif ret == :cancel
          ret = :abort
        end
      end while ret != :next && ret != :abort && ret != :back


      Wizard.RestoreNextButton

      Convert.to_symbol(ret)
    end
  end
end
