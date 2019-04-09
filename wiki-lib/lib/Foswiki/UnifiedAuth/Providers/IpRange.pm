package Foswiki::UnifiedAuth::Providers::IpRange;

use Error;

use strict;
use warnings;

use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub isMyLogin {
    my $this = shift;

    # $this->enabled() did all the work for us...

    return 1;
}

sub isEarlyLogin {
    return 1;
}

sub processLogin {
    my $this = shift;

    my $config = $this->{config};
    return $config->{user_id};
}

1;
