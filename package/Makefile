#
# Makefile for tclrmq package
#
# basically we make a pkgIndex.tcl package file and install stuff
#

PACKAGE=tclrmq
PREFIX=/usr/local
TCLSH=tclsh
PACKAGELIBDIR=$(PREFIX)/lib/$(PACKAGE)
LIBSOURCES= Channel.tcl Connection.tcl Login.tcl encoders.tcl decoders.tcl constants.tcl 

all:    pkgIndex.tcl
	@echo "'make install' to install"

pkgIndex.tcl:   $(LIBSOURCES)
	echo "pkg_mkIndex ." | $(TCLSH)

install:    install-package

install-package:    pkgIndex.tcl
	-mkdir -p $(PACKAGELIBDIR)
	cp *.tcl $(PACKAGELIBDIR)
	cd $(PACKAGELIBDIR); echo "package require tclrmq" | tclsh
	cd $(PACKAGELIBDIR); echo "pkg_mkIndex -verbose . *.tcl" | tclsh

clean:
	rm -f pkgIndex.tcl

