#
# Makefile.am for restore/src
#
# $Id$
#

yncludedir = @yncludedir@/restore

client_DATA =			\
	restore.ycp		\
	restore_auto.ycp

ynclude_DATA =			\
	helps.ycp		\
	summary_dialog.ycp	\
	ui.ycp

config_DATA =			\
	restore.y2cc

desktop_DATA =			\
	restore.desktop

module_DATA =			\
	Restore.ycp

ybin_SCRIPTS = \
	restore_parse_pkginfo.pl

include $(top_srcdir)/Makefile.am.common

restore:
	ln -sf . restore

ycpchook = restore

YCPCFLAGS=-I.

EXTRA_DIST = $(client_DATA) $(ynclude_DATA) $(config_DATA) $(module_DATA) $(desktop_DATA) $(ybin_SCRIPTS)
