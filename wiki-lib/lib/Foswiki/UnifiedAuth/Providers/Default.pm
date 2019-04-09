package Foswiki::UnifiedAuth::Providers::Default;

use Digest::SHA qw(sha1_base64);
use Error;

use strict;
use warnings;

our @ISA = qw(Foswiki::UnifiedAuth::Provider);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub useDefaultLogin {
    return 0;
}

sub initiateLogin {
    my ($this, $origin) = @_;

    my $session = $this->{session};
    my $query = $session->{request};
    my $context = Foswiki::Func::getContext();
    my $topic  = $session->{topicName};
    my $web    = $session->{webName};

    my $state = $this->SUPER::initiateLogin($origin);

    my $path_info = $query->path_info();
    if ( $path_info =~ m/['"]/g ) {
        $path_info = substr( $path_info, 0, ( ( pos $path_info ) - 1 ) );
    }

    $session->{prefs}->setSessionPreferences(
        FOSWIKI_ORIGIN => Foswiki::entityEncode($origin),
        PATH_INFO => Foswiki::entityEncode($path_info),
        UAUTHSTATE => $state
    );

    my $tmpl = $session->templates->readTemplate('uauth');
    my $topicObject = Foswiki::Meta->new( $session, $web, $topic );
    $context->{uauth_login_default} = 1;

    $tmpl = $topicObject->expandMacros($tmpl);
    $tmpl = $topicObject->renderTML($tmpl);
    $tmpl =~ s/<nop>//g;
    $session->writeCompletePage($tmpl);

    return $state;
}

sub isMyLogin {
    my $this = shift;

    my $req = $this->{session}->{request};
    return 0 if $req->param('uauth_external');

    my $state = $req->param('state');
    return 0 unless $state;

    my $uauthlogin = $req->param('uauthlogin');
    return 1 if $uauthlogin && $uauthlogin eq 'default';

    return 0;
}

sub supportsRegistration {
    0;
}

sub processLogin {
    my ($this, $state) = @_;

    my $session = $this->{session};
    my $req = $session->{request};
    my $cgis = $session->getCGISession();
    die with Error::Simple("Login requires a valid session; do you have cookies disabled?") if !$cgis;
    my $saved = $cgis->param('uauth_state') || '';

    my $username = $req->param('username') || '';
    my $password = $req->param('password') || '';
    $req->delete('username', 'password', 'state', 'uauthlogin', 'uauth_provider', 'validation_key', 'uauth_external');

    my $uauth = Foswiki::UnifiedAuth->new();

    my @providers = keys %{$Foswiki::cfg{UnifiedAuth}{Providers}};
    push @providers, '__baseuser' unless grep(/^__baseuser$/, @providers);
    foreach my $name (@providers) {
        next if $name eq '__default';

        my $provider = $uauth->authProvider($session, $name);
        next unless $provider->enabled;
        next unless $provider->useDefaultLogin();

        my $result = $provider->processLoginData($username, $password);
        return $result if $result;
    }
    return undef;
}

sub processUrl {
    my $this = shift;
    my $session = $this->{session};
    return $session->getScriptUrl(1, 'login');
}

1;
