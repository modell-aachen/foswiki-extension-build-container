package Foswiki::Form::Editor;

use strict;
use warnings;

use Foswiki::Form::FieldDefinition ();
# our @ISA = ('Foswiki::Form::Textarea');
our @ISA = ('Foswiki::Form::FieldDefinition');

BEGIN {
  if ( $Foswiki::cfg{UseLocale} ) {
    require locale;
    import locale();
  }
}

sub new {
  my $class = shift;
  return $class->SUPER::new( @_ );
}

sub renderForEdit {
  my ( $this, $topicObject, $value ) = @_;

  require Foswiki::Plugins::WysiwygPlugin::TML2HTML;
  my $converter = new Foswiki::Plugins::WysiwygPlugin::TML2HTML;
  my $html = $converter->convert($value);

  my $cgi = CGI::textarea(
    -class   => $this->cssClasses('foswikiTextarea ma-textarea-cke'),
    -cols    => $this->{cols},
    -rows    => $this->{rows},
    -name    => $this->{name},
    -default => $html
  );
  my $marker = CGI::hidden(
    -name    => $this->{name} . '_CKE_WYSIWYG',
    -default => '1'
  );

  return ( '', "$cgi$marker" );
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: Modell Aachen GmbH <http://www.modell-aachen.de>

Copyright (C) 2008-2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
