VERSION=2.0
RM=rm -rf

prefix=/usr/local
exec_prefix=${prefix}
bindir=${exec_prefix}/bin
datadir=${prefix}/share

all: gnomersvp.plx

gnomersvp.plx: gnomersvp.pl gnomersvp.glade
	$(RM) gnomersvp.plx
	cat gnomersvp.pl gnomersvp.glade > gnomersvp.plx
	chmod +x gnomersvp.plx

install: gnomersvp.plx
	install -D ./gnomersvp.schemas $(DESTDIR)$(datadir)/gconf/schemas/gnomersvp.schemas
	install -D ./gnomersvp.plx $(DESTDIR)$(bindir)/gnomersvp
	install -D ./gnomersvp.desktop $(DESTDIR)$(datadir)/applications/gnomersvp.desktop

clean:
	$(RM) gnomersvp.plx

distclean: clean
	$(RM) *~ \#*\# *.bak
	$(RM) -r debian/gnomersvp build-stamp configure-stamp
	$(RM) gnomersvp.gladep gnomersvp.gladep.bak gnomersvp.glade.bak

tar: distclean
	$(RM) -r /tmp/gnomersvp-$(VERSION)
	mkdir /tmp/gnomersvp-$(VERSION)
	cp -a ./ /tmp/gnomersvp-$(VERSION)
	cd /tmp && tar cvfz gnomersvp-$(VERSION).tar.gz gnomersvp-$(VERSION) --exclude=.cvsignore --exclude=CVS 
	cp /tmp/gnomersvp-$(VERSION).tar.gz ..
	$(RM) -r /tmp/gnomersvp-$(VERSION)

deb: tar
	$(RM) -r /tmp/gnomersvp.builddeb
	mkdir /tmp/gnomersvp.builddeb
	cp ../gnomersvp-$(VERSION).tar.gz /tmp/gnomersvp.builddeb
	cd /tmp/gnomersvp.builddeb && tar xvfz gnomersvp-$(VERSION).tar.gz
	cd /tmp/gnomersvp.builddeb/gnomersvp-$(VERSION) && fakeroot dpkg-buildpackage
	$(RM) -r /tmp/gnomersvp.builddeb/gnomersvp-$(VERSION)
	cp -a /tmp/gnomersvp.builddeb/* ..
	$(RM) -r /tmp/gnomersvp.builddeb

rpm: tar
	rpmbuild -tb ../gnomersvp-$(VERSION).tar.gz

.PHONY: all install clean distclean tar deb rpm
