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

package Foswiki::Form::Select2;

use strict;
use warnings;

use Foswiki::Form::Select ();
use Foswiki::Plugins::JQueryPlugin ();
use Foswiki::Plugins::MoreFormfieldsPlugin ();
our @ISA = ('Foswiki::Form::Select');

use Assert;
use HTML::Entities;

BEGIN {
  if ($Foswiki::cfg{UseLocale}) {
    require locale;
    import locale();
  }
}

sub getOptions {
  my $this = shift;
  my $options = $this->_options_raw;
  return $this->_options_query if $this->isAJAX;
  return $options;
}

sub isAJAX {
  my $this = shift;
  my $options = $this->_options_raw;
  return $options->[0] if @$options && $options->[0] =~ m#^https?://#;
}

sub _options_raw {
  my $this = shift;
  $this->{_rawoptions} = $this->SUPER::getOptions unless defined $this->{_rawoptions};
  return $this->{_rawoptions};
}

sub _options_query {
  my $this = shift;
  my $query = Foswiki::Func::getCgiQuery();
  my @valuesFromQuery = $query->param( $this->{name} );

  # For AJAX-based values, just take whatever we get via query
  my @values = ();
  foreach my $item (@valuesFromQuery) {

    # Item10889: Coming from an "Warning! Confirmation required", often
    # there's an undef item (the, last, empty, one, <-- here)
    if ( defined $item ) {
      foreach my $value ( split( /\s*,\s*/, $item ) ) {
        push @values, $value if defined $value;
      }
    }
  }
  \@values;
}

sub getDefaultValue {
  my $this = shift;
  $this->{default} || $this->param('defaultValue') || '';
}

sub param {
  my ($this, $key) = @_;

  unless (defined $this->{_params}) {
    my ($web, $topic) = @{$this}{'web', 'topic'};
    my $form = Foswiki::Form->new($Foswiki::Plugins::SESSION, $web, $topic);
    my %params = Foswiki::Func::extractParameters($form->expandMacros($this->{attributes}));
    $this->{_params} = \%params;

    $form->getPreference('dummy'); # make sure it's cached
    for my $key ($form->{_preferences}->prefs) {
        next unless $key =~ /^\Q$this->{name}\E_s2_(\w+)$/;
        $this->{_params}{$1} = $form->expandMacros($form->getPreference($key));
    }
  }

  if (defined $key) {
    my $res = $this->{_params}{$key};
    $res = $this->{_defaultsettings}{$key} unless defined $res;
    return $res;
  }
  return $this->{_params};
}

sub cssClasses {
  my $this = shift;
  my $addClass = $this->param('cssClasses');
  push @_, $addClass if $addClass;

  $this->SUPER::cssClasses(@_);
}

sub _maketag {
  my ($tag, $params, $content, $forceempty) = @_;
  my $res = "<$tag";
  while (my ($k, $v) = each(%$params)) {
    $res .= " $k=\"";
    $res .= encode_entities($v, '<>&"');
    $res .= '"';
  }
  $content = '' unless defined $content;
  if ($content eq '' && !$forceempty) {
    return "$res />";
  }
  return "$res>$content</$tag>";
}

sub renderForEdit {
  my ($this, $topicObject, $value) = @_;

  my $choices = '';
  my $choices_count = 0;

  $value = '' unless defined $value;
  $value =~ s/(?:^\s+|\s+$)//;
  my %isSelected = map { $_ => 1 } split(/\s*,\s*/, $value);
  my @options = @{$this->SUPER::getOptions};

  my $url;
  if ($url = $this->isAJAX) {

    my @values = grep { defined $_ && /\S/ } split(/\s*,\s*/, $value);
    my @labels;
    if ($this->param('displayTopic') && $this->param('displaySection')) {
      @labels = $this->mapValuesToLabels(@values);
    }
    while (my $v = shift @values) {
      my %params;
      $params{selected} = 'selected' if $isSelected{$v};
      my $label = $v;
      if (@labels) {
        $params{value} = $v;
        $label = shift @labels;
      }
      $label =~ s/<nop/&lt;nop/g;
      $choices .= _maketag('option', \%params, $label);
      $choices_count++;
    }
  } else {
    foreach my $item (@{$this->_options_raw}) {
      my $option = $item;    # Item9647: make a copy not to modify the original value in the array
      my %params;
      $params{selected} = 'selected' if $isSelected{$option};
      if ($this->{_descriptions}{$option}) {
        $params{title} = $this->{_descriptions}{$option};
      }
      if (defined($this->{valueMap}{$option})) {
        $params{value} = $option;
        $option = $this->{valueMap}{$option};
      }
      $option =~ s/<nop/&lt\;nop/go;
      $choices .= _maketag('option', \%params, $option);
      $choices_count++;
    }
  }
  my $size = $choices_count;
  if ($size > $this->{maxSize}) {
    $size = $this->{maxSize};
  } elsif ($size < $this->{minSize}) {
    $size = $this->{minSize};
  }
  my $params = {
    class => $this->cssClasses('foswikiSelect2Field'),
    name => $this->{name},
    'data-width' => $this->param("width") || 'element',
    'data-allow-clear' => $this->param("allowClear") || 'false',
  };
  $params->{'data-placeholder'} = $this->param('placeholder') if defined $this->param('placeholder');
  $params->{'data-placeholder'} = '' if (not defined $this->param('placeholder')) && $this->param("allowClear");
  $params->{'data-placeholdervalue'} = $this->param('placeholderValue') if defined $this->param('placeholderValue');
  $params->{style} = 'width: '.$this->{size}.'ex;' if $this->{size};
  if (defined $url) {
    $params->{'data-url'} = $url;
    my $apf = $this->param('ajaxPassFields');
    $params->{'data-ajaxpassfields'} = $apf if $apf;
    my $resf = $this->param('resultsFilter');
    $params->{'data-resultsfilter'} = $resf if $resf;
  }
  $params->{'multiple'} = 'multiple' if $this->isMultiValued;
  $params->{'data-limit'} = $this->param('limit') if defined $this->param('limit');
  $params->{'data-tags'} = $this->param('tagging') if defined $this->param('tagging');
  $value =
    _maketag('input', {
      type => 'hidden',
      name => "_$this->{name}_present",
      value => '1',
    }) .
    _maketag('select', $params, $choices, 1);

  $this->addJavascript();
  return ('', $value);
}

sub renderForDisplay {
  my ($this, $format, $value, $attrs) = @_;


  my $displayValue = $this->getDisplayValue($value);
  $format =~ s/\$value\(display\)/$displayValue/g;
  $format =~ s/\$value/$value/g;
  $format =~ s/\$edit\b/$this->renderForEdit($attrs->{meta}, $attrs->{origValue})/eg if $attrs->{meta} && defined $attrs->{origValue};

  return $this->SUPER::renderForDisplay($format, $value, $attrs);
}

sub mapValuesToLabels {
  my ($this, @values) = @_;

  my $session = $Foswiki::Plugins::SESSION;
  my ($mweb, $mtopic) = Foswiki::Func::normalizeWebTopicName(undef, $this->param('displayTopic'));
  my $msec = $this->param('displaySection');
  my ($meta, $text) = Foswiki::Func::readTopic($mweb, $mtopic);
  return @values unless $meta && $meta->haveAccess('VIEW');

  $session->{prefs}->pushTopicContext($mweb, $mtopic);
  if ($this->param('displayParams')) {
    for my $var (split /,/, $this->param('displayParams')) {
      $var =~ s/(?:^\s*|\s*$)//g;
      next unless $var;
      my ($k, $v) = split(/\s*=\s*/, $var, 2);
      Foswiki::Func::setPreferencesValue($k, $v);
    }
  }

  $text =~ s/^.*%STARTSECTION\{(?:\s*name\s*=)?\s*"?$msec"?\s*\}%//s;
  $text =~ s/%(?:STOP|END)SECTION\{(?:\s*name\s*=)?\s*"?$msec"?\s*\}%.*$//s;

  my @res = map { $session->{prefs}->setSessionPreferences(id => $_); $meta->expandMacros($text) } @values;
  $session->{prefs}->popTopicContext();
  @res;
}

sub getDisplayValue {
  my ($this, $value) = @_;

  return '' unless defined $value && $value ne '';

  if ($this->isAJAX) {
    if (my $mtopic = $this->param('displayTopic') and my $msec = $this->param('displaySection')) {
      my @v = $value;
      if ($this->isMultiValued()) {
        @v = split(/\s*,\s*/, $value);
      }
      return join($this->param('separator') || ', ', $this->mapValuesToLabels(@v));
    } else {
      return $value;
    }
  }
  my @v = $value;
  if ($this->isMultiValued()) {
    @v = split(/\s*,\s*/, $value);
  }
  my @res = map { $this->{valueMap}{$_} || $_ } @v;

  return join($this->param('separator') || ', ', @res);;
}

sub addJavascript {
  #my $this = shift;

  Foswiki::Plugins::JQueryPlugin::createPlugin("select2");
  Foswiki::Func::addToZone("script", "FOSWIKI::SELECT2FIELD", <<"HERE", "JQUERYPLUGIN::SELECT2");
<script type='text/javascript' src='%PUBURLPATH%/%SYSTEMWEB%/MoreFormfieldsPlugin/select2field.js?v=$Foswiki::Plugins::MoreFormfieldsPlugin::RELEASE'></script>
HERE
}

# Terrible workaround to allow submitting empty +multi
sub populateMetaFromQueryData {
  my $this = shift;
  my ($query, $meta, $old) = @_;
  if ($this->isMultiValued && scalar $query->multi_param("_$this->{name}_present") && !scalar $query->multi_param($this->{name})) {
    return (0, 1) if ($this->isMandatory);

    # reconstruct title, see original method
    my $title = $this->{title};
    if ($this->{definingTopic}) {
      $title = "[[$this->{definingTopic}][$title]]";
    }
    $meta->putKeyed('FIELD', {
        name => $this->{name},
        title => $title,
        value => '',
    });

    return (1, 1);
  }
  return $this->SUPER::populateMetaFromQueryData(@_);
}

1;
