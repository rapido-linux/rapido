# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

#TODO libexec?
bindir ?= /usr/bin
libdir ?= /usr/lib
pkglibdir ?= ${libdir}/rapido
sysconfdir ?= /etc

.PHONY: install clean test all

all:
	$(info No compilation required.)

clean:
	$(info Nothing to clean up.)

test:
	selftest/selftest.sh

install: all
	install -D -t $(DESTDIR)$(pkglibdir)/cut cut/*.sh
	install -D -t $(DESTDIR)$(pkglibdir)/autorun/lib autorun/lib/*.sh
	install -t $(DESTDIR)$(pkglibdir)/autorun autorun/*.sh
	install -D -t $(DESTDIR)$(pkglibdir)/tools tools/*.sh
	install -m 644 -D -t $(DESTDIR)$(pkglibdir)/dracut.conf.d \
		dracut.conf.d/.empty dracut.conf.d/01-rapido-dracut.conf
	install -t $(DESTDIR)$(pkglibdir) \
		rapido runtime.vars vm.sh vm_autorun.env
	mkdir -p $(DESTDIR)$(bindir) $(DESTDIR)$(sysconfdir)/rapido
	# symlink ensures that RAPIDO_DIR can be found via realpath
	ln -s $(pkglibdir)/rapido $(DESTDIR)$(bindir)/
	install -D tools/bash_completion \
		$(DESTDIR)$(sysconfdir)/bash_completion.d/rapido
	# use etc for configuration, and PWD for all (throwaway) VM image state
	sed -e 's/^#VM_NET_CONF=.*/VM_NET_CONF="\/etc\/rapido\/net-conf"/' \
	    -e 's/^#QEMU_PID_DIR=.*/QEMU_PID_DIR="$$PWD"/' \
	    -e 's/^#DRACUT_OUT=.*/DRACUT_OUT="$${PWD}\/rapido.cpio"/' \
	    rapido.conf.example > $(DESTDIR)$(sysconfdir)/rapido/rapido.conf


.DEFAULT_GOAL = all