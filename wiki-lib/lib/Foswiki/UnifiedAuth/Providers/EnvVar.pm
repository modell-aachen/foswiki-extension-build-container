package Foswiki::UnifiedAuth::Providers::EnvVar;

use strict;
use warnings;

use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub isMyLogin {
    my $this = shift;
    my $cgis = $this->{session}->getCGISession;
    if ($cgis) {
        my $run = $cgis->param('uauth_envvar_failed') || 0;
        return 0 if $run;
    }

    my $cfg = $this->{config};
    $cfg->{identityProvider} ||= '_all_';
    return 1;
}

sub isEarlyLogin {
    return 1;
}

sub initiateLogin {
    my ($this, $origin) = @_;
    my $req = $this->{session}{request};

    return $this->SUPER::initiateLogin($origin);
}

sub handleLogout {
    my ($this, $session) = @_;
    return unless $session;

    my $cgis = $session->getCGISession();
    $cgis->param('uauth_envvar_logged_out', 1);
}

sub processLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $session->getCGISession();
    my $cfg = $this->{config};

    if ($cgis->param('uauth_envvar_logged_out')) {
        Foswiki::Func::writeWarning("Skipping EnvVar, because user logged out.") if $cfg->{debug} && $cfg->{debug} eq 'verbose';
        return 0;
    }

    my $req    = $session->{request};
    my $res = $session->{response};

    my $header = $this->{config}->{header} || 'X-Remote-User';
    my $envvar = $req->header($header);
    unless (defined $envvar) {
        Foswiki::Func::writeWarning("$header header not set in client request.") if $cfg->{debug};
        return 0;
    }

    my $realm = $this->{config}->{realm} || '';
    $envvar =~ s/\@$realm//;

    Foswiki::Func::writeWarning("User '$envvar' logged in by header X-Remote-User.") if $cfg->{debug};
    return $envvar;
}

1;
