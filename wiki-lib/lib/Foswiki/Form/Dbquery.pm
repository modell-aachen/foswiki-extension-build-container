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

package Foswiki::Form::Dbquery;

use strict;
use warnings;
use Foswiki::Func ();
use Foswiki::Form::ListFieldDefinition ();
use Assert;
our @ISA = ('Foswiki::Form::ListFieldDefinition');

BEGIN {
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

sub new {
    my $class = shift;
    my $this  = $class->SUPER::new(@_);

    $this->{_formfieldClass} = 'foswikiDbqueryField';
    $this->{_formfieldClass} .= ' foswikiMandatory' if ($this->{attributes} || '') =~ /M/;

    return $this;
}

sub isMultiValued {
    #return shift->{type} =~ /\+multi/;
    undef;
}
sub isValueMapped { return shift->{type} =~ /\+values/; }

sub getDefaultValue {
    my $this = shift;
    my $val = $this->param('default');
    return defined($val) ? $val : '';
}

sub finish {
  my $this = shift;
  $this->SUPER::finish();
  undef $this->{_params};
}

sub param {
  my ($this, $key) = @_;

  unless (defined $this->{_params}) {
    my %params = Foswiki::Func::extractParameters($this->{value});
    $this->{_params} = \%params;
  }

  return (defined $key)?$this->{_params}{$key}:$this->{_params};
}

sub renderForEdit {
  my ($this, $param1, $param2, $param3) = @_;

  my $value;
  my $web;
  my $topic;
  my $topicObject;
  if (ref($param1)) {    # Foswiki > 1.1
    $topicObject = $param1;
    $value = $param2;
  } else {
    $web = $param1;
    $topic = $param2;
    $value = $param3;
  }

  my @htmlData = ();
  push @htmlData, 'type="hidden"';
  push @htmlData, 'class="'.$this->{_formfieldClass}.'"';
  push @htmlData, 'name="'.$this->{name}.'"';
  push @htmlData, 'value="'.$value.'"';

  my $size = $this->{size};
  if (defined $size) {
    $size .= "em";
  } else {
    $size = "element";
  }
  push @htmlData, 'data-width="'.$size.'"';

  while (my ($key, $val) = each %{$this->param()}) {
    next if $key =~ /^(web|_DEFAULT)$/;
    $key = lc(Foswiki::spaceOutWikiWord($key, "-"));
    push @htmlData, 'data-'.$key.'="'.$val.'"';
  }

  $this->addJavascript();
  $this->addStyles();

  my $field = "<input ".join(" ", @htmlData)." />"; 

  return ('', $field);
}

sub addStyles {
  #my $this = shift;
  Foswiki::Func::addToZone("head", 
    "MOREFORMFIELDSPLUGIN::CSS",
    "<link rel='stylesheet' href='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/moreformfields.css' media='all' />");

}

sub addJavascript {
  #my $this = shift;

  Foswiki::Plugins::JQueryPlugin::createPlugin("select2");
  Foswiki::Func::addToZone("script", "FOSWIKI::DBQUERYFIELD", <<"HERE", "JQUERYPLUGIN::SELECT2");
<script type='text/javascript' src='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/dbqueryfield.js'></script>
HERE
}

1;
