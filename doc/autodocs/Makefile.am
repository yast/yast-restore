#
# Makefile.am for y2c_restore/doc/autodocs
#
# $Id$
#

htmldir = $(docdir)/autodocs

index.html: $(srcdir)/../../src/*.ycp
	@YAST2DIR@/bin/ycpdoc -d. $(srcdir)/../../src/*.ycp

html_DATA = index.html $(wildcard *.html)

CLEANFILES = $(html_DATA)
