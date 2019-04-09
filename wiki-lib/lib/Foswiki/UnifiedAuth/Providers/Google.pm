package Foswiki::UnifiedAuth::Providers::Google;

use Error;
use JSON;
use LWP::UserAgent;
use Net::OAuth2::Profile::WebServer;

use strict;
use warnings;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_google (
            cuid UUID NOT NULL,
            pid INTEGER NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO meta (type, version) VALUES('users_google', 0)"
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub _makeOAuth {
    my $this = shift;
    my $ua = LWP::UserAgent->new;
    my $res = $ua->get("https://accounts.google.com/.well-known/openid-configuration");
    die "Error retrieving Google authentication metadata: ".$res->as_string unless $res->is_success;
    my $json = decode_json($res->decoded_content);
    $this->{oid_cfg} = $json;
    Net::OAuth2::Profile::WebServer->new(
        client_id => $this->{config}{client_id},
        client_secret => $this->{config}{client_secret},
        site => '',
        secrets_in_params => 0,
        authorize_url => $json->{authorization_endpoint},
        access_token_url => $json->{token_endpoint},
    );
}

sub initiateExternalLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $this->{session}->getCGISession();
    my $state = $cgis->param('uauth_state');

    my $auth = $this->_makeOAuth;
    my $uri = $auth->authorize(
        redirect_uri => $this->processUrl(),
        scope => 'openid email profile',
        state => $state,
        hd => $this->{config}{domain},
    );

    $this->{session}{response}->redirect(
        -url     => $uri,
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
    return $req->param('state') && $req->param('code');
}

sub processLogin {
    my $this = shift;
    my $req = $this->{session}{request};
    my $state = $req->param('state');
    $req->delete('state');
    die with Error::Simple("You seem to be using an outdated URL. Please try again.\n") unless $this->SUPER::processLogin($state);

    my $auth = $this->_makeOAuth;
    my $token = $auth->get_access_token($req->param('code'),
        redirect_uri => $this->processUrl(),
    );
    $req->delete('code');
    if ($token->error) {
        die with Error::Simple("Login failed: ". $token->error_description ."\n");
    }
    my $tokenType = $token->token_type;
    $token = $token->access_token;
    my $ua = LWP::UserAgent->new;
    my $acc_info = $ua->simple_request(HTTP::Request->new('GET', $this->{oid_cfg}{userinfo_endpoint},
        ['Authorization', "$tokenType $token"]
    ));
    unless ($acc_info->is_success) {
        die with Error::Simple("Failed to get user information from Google: ". $acc_info->as_string ."\n");
    }

    $acc_info = decode_json($acc_info->decoded_content);
    my $enforceDomain = $this->{config}{enforceDomain} || 0;
    if ($this->{config}{domain} && $enforceDomain) {
        die with Error::Simple("\%BR\%You're *not allowed* to access this site.") unless ($acc_info->{hd} && $acc_info->{hd} eq $this->{config}{domain});
    }

    # email, name, family_name, given_name
    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $pid = $this->getPid();
    $uauth->apply_schema('users_google', @schema_updates);
    my $exist = $db->selectrow_array("SELECT COUNT(login_name) FROM users WHERE login_name=? AND pid=?", {}, $acc_info->{email}, $pid);
    if ($exist == 0) {
        my $user_id;
        my $user_email = $acc_info->{email};
        eval {
            $db->begin_work;
            $user_id = $uauth->add_user('UTF-8', $pid, {
                email => $user_email,
                login_name => $user_email,
                wiki_name => $this->_formatWikiName($acc_info),
                display_name => $this->_formatDisplayName($acc_info)
            });
            $db->do("INSERT INTO users_google (cuid, pid, info) VALUES(?,?,?)", {}, $user_id, $pid,JSON::encode_json($acc_info));
            $db->commit;
        };
        if ($@) {
            my $err = $@;
            eval { $db->rollback; };
            die with Error::Simple("Failed to initialize Google account '$user_email' ($err)\n");
        }

        return $user_id if $this->{config}{identityProvider};
        return {
            cuid => $user_id,
            data => $acc_info,
        };
    }

    # Check if values need updating
    my $userdata = $db->selectrow_hashref("SELECT * FROM users AS u NATURAL JOIN users_google WHERE u.login_name=? AND u.pid=?", {}, $acc_info->{email}, $pid);
    my $cur_dn = $this->_formatDisplayName($acc_info);
    if ($cur_dn ne $userdata->{display_name}) {
        $uauth->update_user('UTF-8', $userdata->{cuid}, {email => $acc_info->{email}, display_name => $cur_dn});
    }

    return $userdata->{login_name} if $this->{config}{identityProvider};
    return {
        cuid => $userdata->{cuid},
        data => $acc_info,
    };
}

sub _formatWikiName {
    my ($this, $data) = @_;
    my $format = $this->{config}{wikiname_format} || '$name';
    _applyFormat($format, $data);
}
sub _formatDisplayName {
    my ($this, $data) = @_;
    my $format = $this->{config}{displayname_format} || '$name';
    _applyFormat($format, $data);
}
sub _applyFormat {
    my ($format, $data) = @_;
    for my $k (keys %$data) {
        $format =~ s/\$$k\b/$data->{$k}/g;
    }
    return $format;
}

1;
