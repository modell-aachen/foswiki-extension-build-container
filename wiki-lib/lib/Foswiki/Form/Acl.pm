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

package Foswiki::Form::Acl;

use strict;
use warnings;

use Foswiki::Form::Checkbox ();

BEGIN {
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

our @ISA = ('Foswiki::Form::Checkbox');

sub new {
    my $class = shift;
    my $this = $class->SUPER::new(@_);
    $this->{size} = 1;
    return $this;
}

sub isValueMapped {
  return 1;
}

sub param {
  my ($this, $key, $topicObject) = @_;

  unless (defined $this->{_params}) {
    my ($web, $topic) = @{$this}{'web', 'topic'};
    my $form = Foswiki::Form->new($Foswiki::Plugins::SESSION, $web, $topic);
    my %params = Foswiki::Func::extractParameters($form->expandMacros($this->{attributes}));
    $this->{_params} = \%params;

    $form->getPreference('dummy'); # make sure it's cached
    for my $key ($form->{_preferences}->prefs) {
        next unless $key =~ /^\Q$this->{name}\E_acl_(\w+)$/;
        $this->{_params}{$1} = $topicObject->expandMacros($form->getPreference($key));
    }
  }

  if (defined $key) {
    my $res = $this->{_params}{$key};
    $res = $this->{_defaultsettings}{$key} unless defined $res;
    return $res;
  }
  return $this->{_params};
}

sub beforeSaveHandler {
  my ($this, $topicObject) = @_;
  my $allowedUsers;

  my $field = $topicObject->get('FIELD', $this->{name});

  unless($field && $field->{value}){
    # No restrictions if it is not checked
    $allowedUsers = "";
  }
  elsif(not $this->param('triggerCondition', $topicObject)){
    # No restriction if the triggerCondition does not hold
    $allowedUsers = "";
  }
  else{
    # Restrict to allowedUsers setting
    $allowedUsers = $this->param('allowedUsers', $topicObject);
  }

  $topicObject->putKeyed('PREFERENCE', {
    name => "ALLOWTOPICVIEW",
    title => "ALLOWTOPICVIEW",
    type => "Set",
    value => $allowedUsers
  });

  $topicObject->putKeyed('PREFERENCE', {
    name => "ALLOWTOPICCHANGE",
    title => "ALLOWTOPICCHANGE",
    type => "Set",
    value => $allowedUsers
  });
}

1;

