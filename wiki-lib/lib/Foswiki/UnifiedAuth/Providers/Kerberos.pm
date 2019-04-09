package Foswiki::UnifiedAuth::Providers::Kerberos;

use strict;
use warnings;

use Error;
use GSSAPI;
use JSON;
use MIME::Base64;

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
        my $run = $cgis->param('uauth_kerberos_failed') || 0;
        return 0 if $run;
    }

    my $cfg = $this->{config};
    unless ($cfg->{realm} && $cfg->{keytab}) {
        Foswiki::Func::writeWarning("Please specify realm and keytab in configure") if $cfg->{debug};
        return 0;
    }
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
    $cgis->param('uauth_kerberos_logged_out', 1);
}

sub processLogin {
    my $this = shift;

    my $session = $this->{session};
    my $cgis = $session->getCGISession();
    my $cfg = $this->{config};

    if ($cgis->param('uauth_kerberos_failed')) {
        Foswiki::Func::writeWarning("Skipping Kerberos, because it failed before") if $cfg->{debug};
        return 0;
    }
    if ($cgis->param('uauth_kerberos_logged_out')) {
        Foswiki::Func::writeWarning("Skipping Kerberos, because user logged out") if $cfg->{debug} && $cfg->{debug} eq 'verbose';
        return 0;
    }

    my $req    = $session->{request};
    my $res = $session->{response};


    my $tried = $cgis->param('uauth_kerberos_run');
    if (!$tried) {
        Foswiki::Func::writeWarning("Asking for kerberos authentification") if $cfg->{debug} && $cfg->{debug} eq 'verbose';
        $cgis->param('uauth_kerberos_run', 1);
        $cgis->param('uauth_provider', $this->{id});

        $res->deleteHeader('WWW-Authenticate');
        $res->header(-status => 401, -WWW_Authenticate => 'Negotiate');
        $res->body('');
        # XXX
        # Unfortunately the user will be presented with an empty page when all
        # these conditions apply (Edge bug?):
        #    * Edge
        #    * not configured for kerberos (local sites)
        #    * user presses 'esc' when NTLM challenge appears
        # This is not because of the body(''), rather the browser gets a
        # complete page but chooses to ignore the body.
        return 'wait for next step';
    }

    my $token = $req->header('authorization');
    unless (defined $token) {
        Foswiki::Func::writeWarning("Client did not send an authorization token, please add wiki to 'Local intranet'") if $cfg->{debug};
        return 0;
    }

    $token =~ s/^Negotiate //;
    if ($token =~ m#^TlRMT#) {
        # have it not use NTLM anymore
        $res->deleteHeader('WWW-Authenticate');
        $res->header(-status => 401);

        Foswiki::Func::writeWarning("Client attempted authorization with a NTLM token. Please add wiki to 'Local intranet'.") if $cfg->{debug};
        my $error = $session->i18n->maketext("Your browser is not correctly configured for the authentication with this wiki. Please add this site to your 'local intranet'. Please contact your administrator for further assistance.");
        $res->deleteHeader('WWW-Authenticate');
        throw Error::Simple($error);
    }
    $token = decode_base64($token);

    if (length($token)) {
        $ENV{KRB5_KTNAME} = "FILE:$cfg->{keytab}";
        my $ctx;
        my $omech = GSSAPI::OID->new;
        my $accept_status = GSSAPI::Context::accept(
            $ctx,
            GSS_C_NO_CREDENTIAL,
            $token,
            GSS_C_NO_CHANNEL_BINDINGS,
            my $client,
            gss_nt_krb5_name,
            my $otoken,
            my $oflags,
            my $otime,
            my $delegated
        );

        if ($otoken) {
            my $enc = encode_base64($otoken);
            $res->deleteHeader('WWW-Authenticate');
            $res->header(-WWW_Authenticate => "Negotiate $enc");
            Foswiki::Func::writeWarning("Adding otoken to response") if $cfg->{debug} && $cfg->{debug} eq 'verbose';
        }

        my $principal;
        my $client_status = $client->display($principal);
        unless ($principal) {
            if($cfg->{debug}) {
                if($accept_status->major()) {
                    Foswiki::Func::writeWarning($accept_status);
                } else {
                    Foswiki::Func::writeWarning($client_status) if $client_status->major();
                }
            }
            $cgis->param('uauth_kerberos_failed', 1);
            my $error = $session->i18n->maketext("The authentication failed (Kerberos error). Please contact your administrator for further assistance.");
            throw Error::Simple($error);
        }

        # ToDo. place an option in configure whether to strip off the realm
        $principal =~ s/\@$cfg->{realm}//;
        Foswiki::Func::writeWarning("Kerberos identified user as '$principal'") if $cfg->{debug};
        return $principal;
    }

    Foswiki::Func::writeWarning("Client sent malformed authorization token");
    return 0;
}

1;
