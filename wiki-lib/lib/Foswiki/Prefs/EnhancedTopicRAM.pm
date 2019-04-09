# See bottom of file for default license and copyright information
package Foswiki::Prefs::EnhancedTopicRAM;

use strict;
use warnings;

use File::Find;
use File::Spec;

use Foswiki::Prefs::TopicRAM;
our @ISA = qw(Foswiki::Prefs::TopicRAM);

my %cache;

sub new {
    my ($proto, $meta) = @_;
    my $this = $proto->SUPER::new($meta);

    if($this->{values}{INHERITED_WEB}) {
        $this->{values}{INHERITED_WEB} =~ s/\s*//g;
    }

    $this->{inheritedDefaultPrefs} = ();

    # Apply default preferences.
    $this->fetchPrefs unless $cache{inited};
    $this->applyPrefs('site') if ($meta->web.".".$meta->topic) eq $Foswiki::cfg{LocalSitePreferences};
    $this->applyPrefs('web') if $meta->topic eq $Foswiki::cfg{WebPrefsTopicName};


    return $this;
}

sub inheritsFrom {
    my ($this) = @_;

    return $this->{values}{INHERITED_WEB};
}

sub fetchPrefs {
  my $this = shift;

  my $meta = $this->{topicObject};
  my $session = $meta->{_session};
  my $plugins = $session->{plugins}{plugins};
  my $dir = File::Spec->catdir(
    $Foswiki::cfg{ScriptDir},
    '..',
    'lib',
    'Foswiki',
    'Contrib'
  );

  opendir(my $dh, $dir) or die "Cannot open directory: $!";
  my @contribs = sort map {
    $_ = Foswiki::Sandbox::untaintUnchecked($_);
    $_ =~ s/\.pm$//;
    $_
  } grep {/(?:Addon|Contrib|Skin).pm$/} readdir($dh);
  closedir($dh);

  my @modules = map {$_->{module}} @$plugins;
  push @modules, @contribs;

  foreach my $module (@modules) {
    next unless $module;
    my $package = _getPackageName($module);
    next if defined $cache{site}{$package} || defined $cache{web}{$package};
    my ($site, $web) = _getPrefs("$module");
    $cache{site}{$package} = $site if defined $site;
    $cache{web}{$package} = $web if defined $web;
  }

  $cache{inited} = 1;
}

sub applyPrefs {
  my ($this, $type) = @_;
  return unless %cache && defined $cache{$type};

  while (my ($package, $prefs) = each %{$cache{$type}}) {
    next unless ref($prefs) eq 'HASH';
    if ($type eq 'site' || ($this->{values}{DEFAULT_SOURCES} || '') =~ /$package/) {
      while (my ($key, $value) = each %$prefs) {
        # We also track which preferences were set by default preferences
        # so we are able to comprehend from the outside where settings come from.
        $this->{inheritedDefaultPrefs}{$key} = {
          module => $package,
          value => $value,
          isOverridden => exists $this->{values}{$key}
        };
        $this->{values}{$key} = $value unless exists $this->{values}{$key};
      }
    }
  }
}

sub stringify {
  my ($this) = @_;
  return '' unless %cache;

  my $meta = $this->{topicObject};
  my $type = 'web' if $meta->topic eq $Foswiki::cfg{WebPrefsTopicName};
  $type = 'site' if $meta->web.'.'.$meta->topic eq $Foswiki::cfg{LocalSitePreferences};
  return '' unless defined $type;

  my (@sitePrefs, @webPrefs, @availPrefs);
  while (my ($package, $prefs) = each %{$cache{$type}}) {
    next unless ref($prefs) eq 'HASH';
    while (my ($key, $value) = each %$prefs) {
      $value = '' unless defined $value;
      $value =~ s/%/%<nop>/g;
      if ($type eq 'site') {
        push @sitePrefs, "   * Set $key = $value <small>(%GREEN%$package%ENDCOLOR%)</small>";
      } elsif (defined $package && defined $this->{values}{DEFAULT_SOURCES} && $this->{values}{DEFAULT_SOURCES} =~ /$package/) {
        push @webPrefs, "   * Set $key = $value <small>(%GREEN%$package%ENDCOLOR%)</small>";
      } else {
        push @availPrefs, "   * Set $key = $value <small>(%GREEN%$package%ENDCOLOR%)</small>";
      }
    }
  }

  my $sitePrefs = join("\n", sort @sitePrefs);
  my $webPrefs = join("\n", sort @webPrefs);
  my $availPrefs = join("\n", sort @availPrefs);

  return $sitePrefs if $type eq 'site';
  return <<PREFS if $type eq 'web';
---++++ Active Preferences
$webPrefs

---++++ Available Preferences
$availPrefs
PREFS

  return '';
}

sub _getPrefs {
  my $mod = shift;

  no strict 'refs';
  unless ($mod =~ /Plugin$/) {
    my $name = $mod;
    return (undef, undef) if $mod eq 'VirtualHostingContrib'; # avoid UI engine monkey-patch
    $mod = "Foswiki::Contrib::$mod";
    require "Foswiki/Contrib/$name.pm" unless ${$mod . '::VERSION'};
  }

  (${$mod . '::SITEPREFS'}, ${$mod . '::WEBPREFS'});
}

sub _getPackageName {
  my $mod = shift;
  $mod =~ s/^Foswiki::(Contrib|Plugins):://;
  $mod =~ s/\.pm$//;
  $mod;
}

1;

__END__
Q.Wiki PreferencesPlugin - Modell Aachen GmbH

Author: Modell Aachen Gmbh

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
