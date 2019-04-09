package Foswiki::UnifiedAuth::IdentityProvider;

use strict;
use warnings;

use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub identify {
  my $this = shift;
  my $login = shift;
}
