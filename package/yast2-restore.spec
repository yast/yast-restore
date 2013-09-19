#
# spec file for package yast2-restore
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via http://bugs.opensuse.org/
#


Name:           yast2-restore
Version:        3.1.0
Release:        0

BuildRoot:      %{_tmppath}/%{name}-%{version}-build
Source0:        %{name}-%{version}.tar.bz2

Group:	        System/YaST
License:        GPL-2.0+
BuildRequires:	perl-XML-Writer update-desktop-files yast2 yast2-testsuite
BuildRequires:  yast2-devtools >= 3.0.6

Requires:	aaa_base
Requires:	bzip2
Requires:	gzip
Requires:	tar
# Wizard::SetDesktopTitleAndIcon
Requires:	yast2 >= 2.21.22
Requires:	yast2-bootloader

BuildArchitectures:	noarch

Requires:       yast2-ruby-bindings >= 1.0.0

Summary:	YaST2 - System Restore

%description
This YaST2 module can restore a system from an archive created by the
Backup module.

%prep
%setup -n %{name}-%{version}

%build
%yast_build

%install
%yast_install


%files
%defattr(-,root,root)

%dir %{yast_yncludedir}/restore
%{yast_yncludedir}/restore/*
%{yast_clientdir}/restore.rb
%{yast_clientdir}/restore_*.rb
%{yast_moduledir}/Restore.rb
%{yast_desktopdir}/restore.desktop
%{yast_ybindir}/restore_parse_pkginfo.pl
%doc %{yast_docdir}
