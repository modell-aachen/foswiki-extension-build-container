package Foswiki::UnifiedAuth::Providers::Steam;

use Error;
use JSON;
use LWP::UserAgent;
use Net::OpenID::Consumer;
use LWPx::ParanoidAgent;
use URI::Escape;
use Cache::FileCache;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_steam (
            cuid UUID NOT NULL,
            pid INTEGER NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO meta (type, version) VALUES('users_steam', 0)"
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub _makeOpenId {
    my $this = shift;

    my $root = Foswiki::Func::getUrlHost();

    my $cgis = $this->{session}->getCGISession();
    my $secret = $cgis->param('steam_secret');
    unless($secret) {
        $secret = rand() . time();
        $cgis->param('steam_secret', $secret);
    }

    my $cache = new Cache::FileCache({ # XXX
        namespace => 'UnifiedAuth_Steam',
    });

    my $req = $this->{session}{request};
    my $args = sub {
        # putting a facade around this, to avoid want_array with param trouble
        if(scalar @_ && defined $_[0]) {
            return $req->param(@_);
        } else {
            return $req->param();
        }
    };

    my $csr = Net::OpenID::Consumer->new(
        ua => LWPx::ParanoidAgent->new(),
        cache => $cache,
        args => $args,
        consumer_secret => $secret,
        required_root => $root,
    );

    return $csr;
}

sub initiateExternalLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $this->{session}->getCGISession();
    my $state = uri_escape($cgis->param('uauth_state'));
    my $root = Foswiki::Func::getUrlHost();
    my $login_script = Foswiki::Func::getScriptUrl(undef, undef, 'login');

    my $csr = $this->_makeOpenId;
    my $claimed_identity = $csr->claimed_identity("http://steamcommunity.com/openid");
    die "error with identity: ".$csr->err() unless $claimed_identity;

    my $check_url = $claimed_identity->check_url(
        return_to => "$login_script?state=$state&steam_oid=1",
        trust_root => $root,
        delayed_return => 1,
    );

    $this->{session}{response}->redirect(
        -url     => $check_url,
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

sub isMyLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $state = $req->param('state');

    return $state && $req->param('steam_oid');
}

sub processLogin {
    my $this = shift;

    my $req = $this->{session}{request};
    my $state = uri_unescape($req->param('state'));
    $req->delete('state');

    unless ($this->SUPER::processLogin($state)) {
        die with Error::Simple("You seem to be using an outdated URL. Please try again.\n");
    }

    my $csr = $this->_makeOpenId;
    $req->delete('steam_oid');

    my $cuid;
    $csr->handle_server_response(
        not_openid => sub {
            Foswiki::Func::writeWarning("Not an openid message");
        },
        setup_needed => sub {
            Foswiki::Func::writeWarning("todo: setup_needed")
        },
        cancelled => sub {
            Foswiki::Func::writeWarning("Login cancelled");
        },
        verified => sub {
            my ($id) = @_;

            return unless $id->display() =~ m#/id/([0-9]+)/?$#;
            my $login = $1;

            my $uauth = Foswiki::UnifiedAuth->new();
            my $db = $uauth->db;
            my $pid = $this->getPid();
            $uauth->apply_schema('users_steam', @schema_updates);

            # TODO: Fetch userinfo using an API-key. I do not have such key, so
            # I will simply use the provided id for everything.
            $cuid = $db->selectrow_array("SELECT cuid FROM users WHERE login_name=? AND pid=?", {}, $login, $pid);
            unless ($cuid) {
                my $charset = 'UTF-8'; # XXX
                my $email = '';
                my $wiki_name = "SteamUser$login";
                $cuid = $uauth->add_user($charset, $pid, {
                    email => $email,
                    login_name => $login,
                    wiki_name => $wiki_name,
                    display_name => $login
                });
                Foswiki::Func::writeWarning("New steam user: $login ($cuid)");
            }
        },
        error => sub {
            my ($errorcode, $errtext ) = @_;
            Foswiki::Func::writeWarning("error: $errorcode $errtext");
        },
    );

    $req->delete('state', 'steam_oid', 'oic.time', 'openid.ns', 'openid.mode', 'openid.op_endpoint', 'openid.claimed_id', 'openid.identity', 'openid.return_to', 'openid.response_nonce', 'openid.assoc_handle', 'openid.signed', 'openid.sig');

    return undef unless $cuid;
    return {
        cuid => $cuid,
        data => {},
    };
}

1;
