package Foswiki::Configure::Checkers::Plugins::CKEditorPlugin::Enabled;

use strict;
use warnings;

use Foswiki::Configure::Checker ();
our @ISA = qw( Foswiki::Configure::Checker );

sub check {
  my $this = shift;
  my $warnings;

  if ( $Foswiki::cfg{Plugins}{CKEditorPlugin}{Enabled} ) {
    if ( !$Foswiki::cfg{Plugins}{JQueryPlugin}{Enabled} ) {
      $warnings .= $this->ERROR(<<'HERE');
CKEditorPlugin depends on JQueryPlugin, which is not enabled.
HERE
    }
  }

  return $warnings;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2013 Modell Aachen GmbH

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
