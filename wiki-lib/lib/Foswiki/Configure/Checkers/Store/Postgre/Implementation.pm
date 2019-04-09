# See bottom of file for default license and copyright information
package Foswiki::Configure::Checkers::Store::Postgre::Implementation;
use strict;
use warnings;

use Foswiki::Configure::Checker ();
our @ISA = ('Foswiki::Configure::Checker');

sub check_current_value {
  my ($this, $reporter) = @_;
  $reporter->ERROR(<<MSG);
Using Foswiki::Store::Postgre as store implementation is NOT supported yet.
MSG
}

1;

__END__
Q.Wiki PostgrePlugin - Modell Aachen GmbH

Author: %$AUTHOR%

Copyright (C) 2016 Modell Aachen GmbH

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
