#
# Makefile.am for y2m_restore/src
#
# $Id$
#

modulesdir = $(YAST2DIR)/modules
clientsdir = $(YAST2DIR)/clients
yncludedir = $(YAST2DIR)/include/restore

clients_DATA =			\
	restore.ycp		\
	restore_write.ycp	\
	restore_auto.ycp

ynclude_DATA =			\
	helps.ycp		\
	misc.ycp		\
	ui.ycp

config_DATA =			\
	restore.y2cc

modules_DATA =			\
	Restore.ycp

EXTRA_DIST = $(clients_DATA) $(ynclude_DATA) $(config_DATA) $(modules_DATA)
