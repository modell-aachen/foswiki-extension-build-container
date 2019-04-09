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

package Foswiki::Form::NetworkAddressField;

use strict;
use warnings;

use Foswiki::Form::Text ();
use Foswiki::Plugins::JQueryPlugin ();
our @ISA = ('Foswiki::Form::Text');

sub addJavascript {
  #my $this = shift;
  Foswiki::Func::addToZone("script", 
    "MOREFORMFIELDSPLUGIN::IPADDRESS::JS",
    "<script src='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/networkaddress.js'></script>", 
    "JQUERYPLUGIN::FOSWIKI, JQUERYPLUGIN::LIVEQUERY, JQUERYPLUGIN::VALIDATE");

  if ($Foswiki::cfg{Plugins}{MoreFormfieldsPlugin}{Debug}) {
    Foswiki::Plugins::JQueryPlugin::createPlugin("debug");
  }

}

sub addStyles {
  #my $this = shift;
  Foswiki::Func::addToZone("head", 
    "MOREFORMFIELDSPLUGIN::CSS",
    "<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/moreformfields.css' media='all' />");

}

sub renderForEdit {
  my $this = shift;

  # get args in a backwards compatible manor:
  my $metaOrWeb = shift;

  my $meta;
  my $web;
  my $topic;

  if (ref($metaOrWeb)) {
    # new: $this, $meta, $value
    $meta = $metaOrWeb;
    $web = $meta->web;
    $topic = $meta->topic;
  } else {
    # old: $this, $web, $topic, $value
    $web = $metaOrWeb;
    $topic = shift;
    ($meta, undef) = Foswiki::Func::readTopic($web, $topic);
  }

  my $value = shift;

  $this->addJavascript();
  $this->addStyles();

  my $required = '';
  if ($this->{attributes} =~ /\bM\b/i) {
    $required = 'required';
  }

  return (
    '',
    CGI::textfield(
      -class => $this->cssClasses('foswikiInputField', $this->{_class}, $required),
      -name => $this->{name},
      -size => $this->{size},
      -value => $value
    )
  );
}

sub renderForDisplay {
  my ($this, $format, $value, $attrs) = @_;

  my $displayValue = $this->getDisplayValue($value);
  $format =~ s/\$value\(display\)/$displayValue/g;
  $format =~ s/\$value/$value/g;

  return $this->SUPER::renderForDisplay($format, $value, $attrs);
}

sub getDisplayValue {
  my ($this, $value) = @_;

  $this->addStyles();

  return "<div class='" . $this->{_class} . "'>$value</div>";
}


1;
