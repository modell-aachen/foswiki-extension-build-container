# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# MoreFormfieldsPlugin is Copyright (C) 2010-2014 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Form::Ipaddress;

use strict;
use warnings;

use Foswiki::Form::NetworkAddressField ();
our @ISA = ('Foswiki::Form::NetworkAddressField');

sub new {
  my $class = shift;
  my $this = $class->SUPER::new(@_);
  $this->{_class} = 'foswikiIpAddress';
  return $this;
}

1;
