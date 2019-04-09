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

package Foswiki::Form::Icon;

use strict;
use warnings;

use YAML ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Form::FieldDefinition ();
our @ISA = ('Foswiki::Form::FieldDefinition');

our %icons = ();

BEGIN {
  if ($Foswiki::cfg{UseLocale}) {
    require locale;
    import locale();
  }
}

sub new {
  my $class = shift;
  my $this = $class->SUPER::new(@_);

  my $size = $this->{size} || '';
  $size =~ s/\D//g;
  $size = 10 if (!$size || $size < 1);
  $this->{size} = $size;

  if ($this->{type} =~ /\+/) {
    my %modifiers = map {lc($_) => 1} grep {!/^icon$/} split(/\+/,$this->{type});
    @{$this->{modifiers}} = keys %modifiers;
    $this->{groupPattern} = join("|", @{$this->{modifiers}});
  }

  $this->{hasMultipleGroups} = (!defined($this->{modifiers}) || scalar(@{$this->{modifiers}}) > 1);

  return $this;
}

sub renderForEdit {
  my ($this, $topicObject, $value) = @_;

  Foswiki::Plugins::JQueryPlugin::createPlugin("fontawesome");
  Foswiki::Plugins::JQueryPlugin::createPlugin("select2");

  Foswiki::Func::addToZone("script", "FOSWIKI::ICONFIELD", <<'HERE', "JQUERYPLUGIN::FONTAWESOME, JQUERYPLUGIN::SELECT2");
<script type='text/javascript' src='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/iconfield.js'></script>
HERE

  $this->readIcons();

  my $html = "<select class='".$this->cssClasses("foswikiFontAwesomeIconPicker")."' style='width:".$this->{size}."em' name='".$this->{name}."'>\n";
  $html .= '<option></option>';
  foreach my $group (sort keys %icons) {
    next if $this->{groupPattern} && $group !~ /$this->{groupPattern}/i;

    my $groupLabel = $group;
    $groupLabel =~ s/^FamFamFam//;
    $groupLabel =~ s/([a-z])([A-Z0-9])/$1 $2/g;

    $html .= "  <optgroup label='$groupLabel'>\n" if scalar$this->{hasMultipleGroups};

    foreach my $entry (sort {$a->{id} cmp $b->{id}} @{$icons{$group}}) {
      my $text = $entry->{id};
      $text =~ s/^fa\-//;
      $html .= "    <option value='$entry->{id}'".($value && $entry->{id} eq $value?"selected":"")." ".($entry->{url}?"data-url='$entry->{url}'":"").">$text</option>\n";
    }

    $html .= "  </optgroup>\n" if $this->{hasMultipleGroups};
  }
  $html .= "</select>\n";

  return ('', $html);
}

sub readIcons {
  my $this = shift;

  return if %icons;

  # read fontawesome icons
  my $iconFile = $Foswiki::cfg{PubDir}.'/'.$Foswiki::cfg{SystemWebName}.'/MoreFormfieldsPlugin/icons.yml';

  my $yml = YAML::LoadFile($iconFile); 

  my $numIcons = 0;
  foreach my $entry (@{$yml->{icons}}) {
    $entry->{id} = 'fa-'.$entry->{id};
    foreach my $cat (@{$entry->{categories}}) {
      push @{$icons{$cat}}, $entry;
      if ($entry->{aliases}) {
        foreach my $alias (@{$entry->{aliases}}) {
          my %clone = %$entry;
          $clone{id} = 'fa-'.$alias;
          $clone{_isAlias} = 1;
          push @{$icons{$cat}}, \%clone;
        }
      }
      $numIcons += scalar(@{$icons{$cat}});
    }
  }

  # read icons from icon path
  my $iconSearchPath = $Foswiki::cfg{JQueryPlugin}{IconSearchPath}
    || 'FamFamFamSilkIcons, FamFamFamSilkCompanion1Icons, FamFamFamSilkCompanion2Icons, FamFamFamSilkGeoSilkIcons, FamFamFamFlagIcons, FamFamFamMiniIcons, FamFamFamMintIcons';

  my @iconSearchPath = split( /\s*,\s*/, $iconSearchPath );

  foreach my $item (@iconSearchPath) {
      my ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName(
          $Foswiki::cfg{SystemWebName}, $item );

      my $iconDir =
          $Foswiki::cfg{PubDir} . '/'
        . $web . '/'
        . $topic . '/';

      opendir(my $dh, $iconDir) || next;
      foreach my $icon (grep { /\.(png|gif|jpe?g)$/i } readdir($dh)) {
        next if $icon =~ /^(SilkCompanion1Thumb|index_abc|igp_.*)\.png$/; # filter some more
        my $id = $icon;
        $id =~ s/\.(png|gif|jpe?g)$//i;
        push @{$icons{$topic}}, {
          id => $id,
          name => $id,
          url => Foswiki::Func::getPubUrlPath() . '/' . $web . '/' . $topic . '/' . $icon,
          categories => [$topic],
        };
      }
      closedir $dh;

      #print STDERR "no icons at $web.$topic\n" unless $icons{$topic};

      $numIcons += scalar(@{$icons{$topic}}) if $icons{$topic};
  }

  #print STDERR "num icons found: $numIcons\n";
}

sub renderForDisplay {
    my ( $this, $format, $value, $attrs ) = @_;

    Foswiki::Plugins::JQueryPlugin::createPlugin("fontawesome");

    my $displayValue = $this->getDisplayValue($value);
    $format =~ s/\$value\(display\)/$displayValue/g;
    $format =~ s/\$value/$value/g;

    return $this->SUPER::renderForDisplay( $format, $value, $attrs );
}

sub getDisplayValue {
    my ( $this, $value ) = @_;

    my $icon = Foswiki::Plugins::JQueryPlugin::handleJQueryIcon($this->{session}, {
      _DEFAULT => $value
    });

    my $text = $value;
    $text =~ s/^fa\-//;
    return $icon.' '.$text;
}

1;
