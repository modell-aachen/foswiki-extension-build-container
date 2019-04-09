# See bottom of file for license and copyright information
package Foswiki::Form::Firstallcheckbox;

use strict;
use warnings;
use Assert;

use Foswiki::Form::Checkbox ();
our @ISA = ('Foswiki::Form::Checkbox');

BEGIN {
    if ( $Foswiki::cfg{UseLocale} ) {
        require locale;
        import locale();
    }
}

sub new {
    my ( $class, @args ) = @_;
    $class->SUPER::new(@args);
}

sub renderForEdit {
    my ( $this, $topicObject, $value ) = @_;

    my $session = $this->{session};
    my $extra   = '';
    $value = '' unless defined($value) && length($value);
    my %isSelected = map { $_ => 1 } split( /\s*,\s*/, $value );
    my %attrs;
    my @defaults;
    foreach my $item ( @{ $this->getOptions() } ) {

        my $title = $item;
        $title = $this->{_descriptions}{$item}
          if $this->{_descriptions}{$item};

        # NOTE: Does not expand $item in title
        $attrs{$item} = {
            class => $this->cssClasses('foswikiCheckbox'),
            title => $topicObject->expandMacros($title),
        };

        if ( $isSelected{$item} ) {

            # One or the other; not both, or CGI generates two checked="checked"
            if ( $this->isValueMapped() ) {
                $attrs{$item}{checked} = 'checked';
            }
            else {
                push( @defaults, $item );
            }
        }
    }
    my %params = (
        -name       => $this->{name},
        -values     => $this->getOptions(),
        -defaults   => \@defaults,
        -columns    => $this->{size},
        -attributes => \%attrs,
        -override   => 1,
    );
    if ( defined $this->{valueMap} ) {
        $params{-labels} = $this->{valueMap};
    }
    my $class = "firstallcheckbox";
    $class .= ' lastcheckbox' if $this->{type} =~ /\+last\b/;
    $value = '<div class="'.$class.'">'. CGI::checkbox_group(%params) .'</div>';

    # Item2410: We need a dummy control to detect the case where
    #           all checkboxes have been deliberately unchecked
    # Item3061:
    # Don't use CGI, it will insert the sticky value from the query
    # once again and we need an empty field here.
    $value .= '<input type="hidden" name="' . $this->{name} . '" value="" />';

    Foswiki::Func::addToZone('script', 'firstallcheckbox::script', <<'EOS');
<script type="text/javascript">
jQuery(function($) {
  $('.firstallcheckbox').each(function() {
    var cons, cdr = $(this).find('input[type="checkbox"]');
    if ($(this).is('.lastcheckbox')) {
      cons = cdr.last();
      cdr = cdr.slice(0, -1);
    } else {
      cons = cdr.first()
      cdr = cdr.slice(1);
    }
    cons.change(function() {
      if ($(this).is(':checked')) {
        cdr.prop('checked', false);
      }
    });
    cdr.change(function() {
      if ($(this).is(':checked')) {
        cons.prop('checked', false);
      }
    });
  });
});
</script>
EOS

    return ( $extra, $value );
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2012 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 2005-2007 TWiki Contributors. All Rights Reserved.
TWiki Contributors are listed in the AUTHORS file in the root
of this distribution. NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
