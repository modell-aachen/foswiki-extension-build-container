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

package Foswiki::Form::Phonenumber;

use strict;
use warnings;

use Foswiki::Form::Text ();
our @ISA = ('Foswiki::Form::Text');

sub addStyles {
  #my $this = shift;
  Foswiki::Func::addToZone("head", 
    "MOREFORMFIELDSPLUGIN::CSS",
    "<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/moreformfields.css' media='all' />");

}

sub addJavascript {
  #my $this = shift;
  Foswiki::Func::addToZone("script", 
    "MOREFORMFIELDSPLUGIN::PHONENUMBER::JS",
    "<script src='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/phonenumber.js'></script>", 
    "JQUERYPLUGIN::FOSWIKI, JQUERYPLUGIN::LIVEQUERY, JQUERYPLUGIN::VALIDATE");

  if ($Foswiki::cfg{Plugins}{MoreFormfieldsPlugin}{Debug}) {
    Foswiki::Plugins::JQueryPlugin::createPlugin("debug");
  }

}

sub renderForEdit {
  my ($this, $topicObject, $value) = @_;

  $this->addJavascript();
  $this->addStyles();

  return (
    '',
    CGI::textfield(
      -class => $this->cssClasses('foswikiInputField foswikiPhoneNumber'),
      -name => $this->{name},
      -size => $this->{size},
      -value => $value
    )
  );
}

sub renderForDisplay {
  my ($this, $format, $value, $attrs) = @_;

  return '' unless defined $value && $value ne '';

  my $displayValue = $this->getDisplayValue($value);
  $format =~ s/\$value\(display\)/$displayValue/g;
  $format =~ s/\$value/$value/g;

  $this->addStyles();
  $this->addJavascript();

  return $this->SUPER::renderForDisplay($format, $value, $attrs);
}

sub getDisplayValue {
  my ($this, $value) = @_;

  my $number = $value;
  $number =~ s/^\s+//;
  $number =~ s/\s+$//;
  $number =~ s/\s+//g;
  $number =~ s/\(.*?\)//g;
  $number =~ s/^\+/00/;

  return "<a href='sip:$number' class='foswikiPhoneNumber'>$value</a>";
}

1;
