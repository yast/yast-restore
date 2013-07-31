# Sources for restore

module_DATA = \
  modules/Restore.rb

client_DATA = \
  clients/restore.rb \
  clients/restore_bootloader.rb \
  clients/restore_auto.rb

yncludedir = @yncludedir@/restore
ynclude_DATA = \
  include/restore/summary_dialog.rb \
  include/restore/ui.rb \
  include/restore/helps.rb

ybin_SCRIPTS = \
  bin/restore_parse_pkginfo.pl

desktop_DATA = \
  desktop/restore.desktop

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(ybin_SCRIPTS) $(desktop_DATA)

include $(top_srcdir)/Makefile.am.common