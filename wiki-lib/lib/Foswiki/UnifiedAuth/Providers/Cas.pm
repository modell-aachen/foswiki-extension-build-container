package Foswiki::UnifiedAuth::Providers::Cas;

use Error;
use JSON;
use AuthCAS;
use URI::Escape;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_cas (
            cuid UUID NOT NULL,
            pid INTEGER NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO meta (type, version) VALUES('users_cas', 0)"
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub _getCas {
    my ($this) = @_;

    return new AuthCAS(
        casUrl      => $this->{config}{casUrl},
        CAFile      => $this->{config}{CAFile},
        SSL_version => $this->{config}{SSL_version},
    );
}

# Will either redirect us to the logout page of our cas or simply set a flag
# that prevents us from simply logging in again.
sub handleLogout {
    my ($this, $session, $user) = @_;
    return unless $session;

    if($this->{config}{LogoutFromCAS}) {
        # redirect to cas logout page
        $session->redirect($this->_getLogoutUrl());
    } else {
        # This will be checked in 'isMyLogin' and make the wiki not to redirect
        # to the cas login or process the login.
        # XXX no way to reset this!
        my $cgis = $session->getCGISession();
        $cgis->param('uauth_cas_logged_out', 1);
    }
}

# Will redirect us to the cas provider.
sub initiateExternalLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $this->{session}->getCGISession();
    my $state = $cgis->param('uauth_state');

    my $cas = $this->_getCas();

    my $casurl = $cas->getServerLoginURL(_fwLoginScript($state));

    $this->{session}{response}->redirect(
        -url     => $casurl,
        -cookies => $session->{response}->cookies(),
        -status  => '302',
    );
    return 1;
}

sub initiateLogin {
    my ($this, $origin) = @_;

    my $req = $this->{session}{request};
    return if $req->param('state');

    return $this->SUPER::initiateLogin($origin);
}

# We always claim this is our login, because if nobody is logged in, we want to
# redirect to our cas provider - unless the user explicitly logged out.
sub isMyLogin {
    my $this = shift;

    my $req = $this->{session}{request};

    my $cgis = $this->{session}->getCGISession();
    return 0 if $cgis->param('uauth_cas_logged_out');

    # grab this login, if it is not ours, we will initiate an external login
    return 1;
}

sub isEarlyLogin {
    return 1;
}

#    * Creates a state if we have none.
#    * Redirects to cas login if not already done so.
#    * If we have a ticked: process it and let me in already!
#       * We will grab the cuid of some user with the same login-name, unless
#         identityProvider is configured (this will be delegated to
#         UnifiedLogin->processProviderLogin).
#
sub processLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $state = $req->param('state');
    my $ticket = $req->param('ticket');
    my $iscas_login = $req->param('cas_login');

    # down below we will delete cas_attempted, but only if the login was
    # successful, so we do not redirect in circles
    $req->delete('state', 'cas_login', 'ticket');

    # we may not have a state, because we grabbed any 'isMyLogin' (UnifiedAuth
    # did not 'initiateLogin').
    if($state) {
        unless ($this->SUPER::processLogin($state)) {
            # this should not happen, the redirect url seems to be mangled
            undef $state;
            Foswiki::Func::writeWarning("ERROR: super failed");
        }
    } else {
        # XXX duplicating code from UnifiedLogin.pm
        $state = $this->initiateLogin($req->param('foswiki_origin') || '');
    }

    unless($iscas_login) {
        $this->initiateExternalLogin() unless $req->param('cas_attempted');
        return 0;
    }

    unless($state && $ticket) {
        die with Error::Simple("You seem to be using an outdated URL. Please try again.\n");
    }

    my $cas = $this->_getCas();
    my $casUser = $cas->validateST( _fwLoginScript($state), $ticket );
    unless ($casUser) {
        Foswiki::Func::writeWarning("casUser undef");
        die with Error::Simple("CAS login failed (could not validate). Please try again.\n");
    }

    if (   $Foswiki::cfg{CAS}{AllowLoginUsingEmailAddress} && $casUser =~ /@/ ) {
        my $login = $this->{session}->{users}->findUserByEmail($casUser);
        $casUser = $login->[0] if ( defined( $login->[0] ) );
    }

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $pid = $this->getPid();
    $uauth->apply_schema('users_cas', @schema_updates);

    # Grab cuid if there is no identityProvider.
    # XXX When UnifiedLogin does not find any cuid in that identityProvider,
    # we will be redirected in circles.
    my $identityProviders = $this->{config}{identityProvider};
    unless($identityProviders) {
        # use cuid from any provider
        my $cuid = $db->selectrow_array("SELECT cuid FROM users WHERE login_name=?", {}, $casUser);
        unless ($cuid) {
            Foswiki::Func::writeWarning("Could not find cuid for user $casUser");
            die with Error::Simple("Could not find your cuid. Please try again.\n");
        }

        $casUser = { cuid => $cuid, data => {} } if $cuid;
    }

    $req->delete('cas_attempted');

    return $casUser;
}

# Generate a login-url we can redirect to.
# It should contain our state and the cas_login marker. Also it will include a
# cas_attempted flag, which stops us redirecting if anything goes wrong.
sub _fwLoginScript {
    my $state = shift;

    # Note: in total we need to escape the state twice, because one will be
    # consumed by the redirect from cas
    my $state_escaped = uri_escape($state || '');

    my $login_script = Foswiki::Func::getScriptUrl(undef, undef, 'login');

    return uri_escape("$login_script?state=$state_escaped&cas_login=1&cas_attempted=1");
}

# Get url we need to redirect to in order to log out from cas.
sub _getLogoutUrl {
    my $this = shift;

    my $session = $this->{session};
    my $req = $session->{request};
    my $uri = Foswiki::Func::getUrlHost() . $req->uri();

    #remove any urlparams, as they will be in the cachedQuery
    $uri =~ s/\?.*$//;
    return $this->_getCas()->getServerLogoutURL(
        Foswiki::urlEncode( $uri . $session->cacheQuery() )
    );
}
1;
