%define ver      2.0
%define rel      0

Summary: GnomeRSVP
Name: gnomersvp
Version: %ver
Release: %rel
License: GPL
Group: Applications/Text
Source: http://www.icebreaker.net/gnomersvp/gnomersvp-%{ver}.tar.gz
BuildRoot: %{_tmppath}/gnomersvp-%{PACKAGE_VERSION}-root
URL: http://www.icebreaker.net/gnomersvp
Requires: perl-Gnome2 >= 1.020, perl-Gnome2-Canvas >= 1.002, perl-Gtk2-GladeXML >= 1.001

%description 
Rapid Serial Visual Projection is the process of blasting
words onto the screen.  In this dynamic representation of text, each word
is flashed on the screen one at a time in succession.  The reader is less
inclined to "oralize" the text, rather the reader interprets whole words
as meaningful written symbols. Automatic re-reading of adjacent previous
text is therefore rendered impossible. This results in much higher reading
speeds than are possible with standard techniques.

%prep
%setup

%build
%{__perl} ./Build

##fix the path in the executable
%{__perl} -pi -e "s,\/usr\/bin\/perl,%{__perl},g" gnomersvp.plx

##fix the path in the desktop file
%{__perl} -pi -e "s,\/usr\/bin\/gnomersvp\.plx,%{_bindir}/gnomersvp,g" gnomersvp.desktop

%install
rm -rf $RPM_BUILD_ROOT

## Next line commented since "install -D" is broken option
###%{__perl} ./INSTALL $RPM_BUILD_ROOT%{_prefix}
%{__mkdir} -p $RPM_BUILD_ROOT%{_bindir} 
%{__install} -m755 ./gnomersvp.plx $RPM_BUILD_ROOT%{_bindir}/gnomersvp
%{__mkdir} -p $RPM_BUILD_ROOT%{_datadir}/gnome/apps/Applications/ 
%{__install} -m644 ./gnomersvp.desktop $RPM_BUILD_ROOT%{_datadir}/gnome/apps/Applications/

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-, root, root)

%doc AUTHORS README THANKS
%{_bindir}/*
%{_datadir}/gnome/apps/Applications/gnomersvp.desktop

%changelog
* Tue May 29 2001 Joel Young <jdy@cs.brown.edu>
- cleaned up rpm to use more standard macros for compatibility
- ./INSTALL script broken so just install from RPM
- path in perl scripts maybe wrong so just execute with perl
- path in binary (perl script) maybe wrong so set to macro value
- path in desktop file maybe wrong so set to macro value
- install to binary name rather than name.plx
