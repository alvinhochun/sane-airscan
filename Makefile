# USER-SETTABLE VARIABLES
#
# The following variables can be overridden by user (i.e.,
# make install DESTDIR=/tmp/xxx):
#
#   Name     Default                  Description
#   ----     -------                  -----------
#   DESTDIR                           Destination directory for make install
#   PREFIX       	              Non-standard: appended to DESTDIR
#   CC       gcc                      C compiler
#   CPPFLAGS                          C preprocessor flags
#   CFLAGS   -O2 -g -W -Wall -Werror  C compiler flags
#   LDFLAGS                           Linker flags
#   COMPRESS gzip                     Program to compress man page, or ""
#   MANDIR   /usr/share/man/          Where to install man page
#   STRIP    -s                       Stripping of debug symbols

CC	= gcc
COMPRESS = gzip
CFLAGS	+= -O2 -g -W -Wall -Werror $(CPPFLAGS)
MANDIR	= /usr/share/man/
PKG_CONFIG = /usr/bin/pkg-config
STRIP 	= -s

# These variables are not intended to be user-settable
OBJDIR  = objs/
BINDIR 	= /usr/bin
CONFDIR = /etc/sane.d
LIBDIR 	:= $(shell $(PKG_CONFIG) --variable=libdir sane-backends)
BACKEND = libsane-airscan.so.1
DISCOVER = airscan-discover
LIBAIRSCAN = $(OBJDIR)/libairscan.a
MAN_DISCOVER = $(DISCOVER).1
MAN_DISCOVER_TITLE = "SANE Scanner Access Now Easy"
MAN_BACKEND = sane-airscan.5
MAN_BACKEND_TITLE = "AirScan (eSCL) and WSD SANE backend"
DEPS_COMMON := avahi-client avahi-glib libsoup-2.4 libxml-2.0
DEPS_CODECS := libjpeg libpng

# Sources and object files
SRC	= $(wildcard airscan-*.c) sane_strstatus.c
OBJ	= $(addprefix $(OBJDIR), $(SRC:.c=.o))

# Obtain CFLAGS and LDFLAGS for dependencies
deps_CFLAGS		:= $(foreach lib, $(DEPS_COMMON), $(shell pkg-config --cflags $(lib)))
deps_CFLAGS		+= $(foreach lib, $(DEPS_CODECS), $(shell pkg-config --cflags $(lib)))

deps_LIBS 		:= $(foreach lib, $(DEPS_COMMON), $(shell pkg-config --libs $(lib))) -lm
deps_LIBS_CODECS 	:= $(foreach lib, $(DEPS_CODECS), $(shell pkg-config --libs $(lib)))

# Compute CFLAGS and LDFLAGS for backend and tools
#
# Note, CFLAGS are common, for simplicity, while LDFLAGS are not, to
# avoid linking unneeded libraries
common_CFLAGS		:= $(CFLAGS) $(deps_CFLAGS)
common_CFLAGS 		+= -fPIC

backend_LDFLAGS 	:= $(LDFLAGS)
backend_LDFLAGS 	+= $(deps_LIBS) $(deps_LIBS_CODECS)
backend_LDFLAGS 	+= -Wl,--version-script=airscan.sym

tools_LDFLAGS 		:= $(LDFLAGS)
tools_LDFLAGS 		+= $(deps_LIBS)
tools_LDFLAGS 		+= -fPIE

tests_LDFLAGS		:= $(tools_LDFLAGS) $(deps_LIBS_CODECS)

# This magic is a workaround for libsoup bug.
#
# We are linked against libsoup. If SANE backend goes unloaded
# from the memory, all libraries it is linked against also will
# be unloaded (unless main program uses them directly).
#
# Libsoup, unfortunately, doesn't unload correctly, leaving its
# types registered in GLIB. Which sooner or later leads program to
# crash
#
# The workaround is to prevent our backend's shared object from being
# unloaded when not longer in use, and these magical options do it
# by adding NODELETE flag to the resulting ELF shared object
backend_LDFLAGS += -Wl,-z,nodelete

$(OBJDIR)%.o: %.c Makefile airscan.h
	mkdir -p $(OBJDIR)
	$(CC) -c -o $@ $< $(CPPFLAGS) $(common_CFLAGS)

.PHONY: all clean install man

all:	tags $(BACKEND) $(DISCOVER) test test-decode

tags: $(SRC) airscan.h test.c test-decode.c
	-ctags -R .

$(BACKEND): $(OBJDIR)airscan.o $(LIBAIRSCAN) airscan.sym
	$(CC) -o $(BACKEND) -shared $(OBJDIR)/airscan.o $(LIBAIRSCAN) $(backend_LDFLAGS)

$(DISCOVER): $(OBJDIR)discover.o $(LIBAIRSCAN)
	 $(CC) -o $(DISCOVER) discover.c $(CPPFLAGS) $(common_CFLAGS) $(LIBAIRSCAN) $(tools_LDFLAGS)

$(LIBAIRSCAN): $(OBJ) Makefile
	ar cru $(LIBAIRSCAN) $(OBJ)

install: all
	mkdir -p $(DESTDIR)$(PREFIX)$(BINDIR)
	mkdir -p $(DESTDIR)$(PREFIX)$(CONFDIR)
	mkdir -p $(DESTDIR)$(PREFIX)$(CONFDIR)/dll.d
	install $(STRIP) -D -t $(DESTDIR)$(PREFIX)$(BINDIR) $(DISCOVER)
	cp -n airscan.conf $(DESTDIR)$(PREFIX)$(CONFDIR)
	cp -n dll.conf $(DESTDIR)$(PREFIX)$(CONFDIR)/dll.d/airscan
	install $(STRIP) -D -t $(DESTDIR)$(PREFIX)$(LIBDIR)/sane $(BACKEND)
	mkdir -p $(DESTDIR)$(PREFIX)/$(MANDIR)/man5
	install -m 644 -D -t $(DESTDIR)$(PREFIX)$(MANDIR)/man1 $(MAN_DISCOVER)
	install -m 644 -D -t $(DESTDIR)$(PREFIX)$(MANDIR)/man5 $(MAN_BACKEND)
	[ "$(COMPRESS)" = "" ] || $(COMPRESS) -f $(DESTDIR)$(PREFIX)$(MANDIR)/man1/$(MAN_DISCOVER)
	[ "$(COMPRESS)" = "" ] || $(COMPRESS) -f $(DESTDIR)$(PREFIX)$(MANDIR)/man5/$(MAN_BACKEND)

clean:
	rm -f test $(BACKEND) tags
	rm -rf $(OBJDIR)

uninstall:
	rm -f $(DESTDIR)$(PREFIX)$(BINDIR)/$(DISCOVER)
	rm -f $(DESTDIR)$(PREFIX)$(CONFDIR)/dll.d/airscan
	rm -f $(DESTDIR)$(PREFIX)$(LIBDIR)/sane/$(BACKEND)
	rm -f $(DESTDIR)$(PREFIX)$(MANDIR)/man1/$(MAN_DISCOVER)*
	rm -f $(DESTDIR)$(PREFIX)$(MANDIR)/man5/$(MAN_BACKEND)*

man: $(MAN_DISCOVER) $(MAN_BACKEND)

$(MAN_DISCOVER): $(MAN_DISCOVER).md
	ronn --roff --manual=$(MAN_DISCOVER_TITLE) $(MAN_DISCOVER).md

$(MAN_BACKEND): $(MAN_BACKEND).md
	ronn --roff --manual=$(MAN_BACKEND_TITLE) $(MAN_BACKEND).md

test:	$(BACKEND) test.c
	$(CC) -o test test.c $(BACKEND) -Wl,-rpath . $(LDFLAGS) ${common_CFLAGS}

test-decode: test-decode.c $(LIBAIRSCAN)
	 $(CC) -o test-decode test-decode.c $(CPPFLAGS) $(common_CFLAGS) $(LIBAIRSCAN) $(tests_LDFLAGS)
