# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::LoginManager::UnifiedLogin

=cut

package Foswiki::LoginManager::UnifiedLogin;

use strict;
use warnings;
use Assert;

use JSON;
use Unicode::Normalize;
use Error ':try';
use Error::Simple;

use Foswiki::LoginManager ();
use Foswiki::Users::BaseUserMapping;
use Foswiki::UnifiedAuth::Providers::BaseUser;

our @ISA = ('Foswiki::LoginManager');

sub new {
    my ( $class, $session ) = @_;
    my $this = $class->SUPER::new($session);
    $session->enterContext('can_login');
    if ( $Foswiki::cfg{Sessions}{ExpireCookiesAfter} ) {
        $session->enterContext('can_remember_login');
    }

    # re-registering these, so we use our own methods.
    Foswiki::registerTagHandler( 'LOGOUT',           \&_LOGOUT );
    Foswiki::registerTagHandler( 'LOGOUTURL',        \&_LOGOUTURL );

    return $this;
}

# Pack key request parameters into a single value
# Used for passing meta-information about the request
# through a URL (without requiring passthrough)
# Copied from TemplateLogin
sub _packRequest {
    my ( $uri, $method, $action ) = @_;
    return '' unless $uri;
    if ( ref($uri) ) {    # first parameter is a $session
        my $r = $uri->{request};
        $uri    = $r->uri();
        $method = $r->method() || 'UNDEFINED';
        $action = $r->action();
    }
    return "$method,$action,$uri";
}

# Unpack single value to key request parameters
sub _unpackRequest {
    my $packed = shift || '';
    my ( $method, $action, $uri ) = split( ',', $packed, 3 );
    return ( Foswiki::urlDecode($uri), $method, $action );
}

sub _authProvider {
    my ($this, $provider) = @_;

    $this->{uac} = Foswiki::UnifiedAuth->new unless $this->{uac};
    $this->{uac}->authProvider($this->{session}, $provider);
}

sub forceAuthentication {
    my $this    = shift;
    my $session = $this->{session};

    unless ( $session->inContext('authenticated') ) {
        my $query    = $session->{request};
        my $response = $session->{response};

        my $authid = $Foswiki::cfg{UnifiedAuth}{DefaultAuthProvider};
        if ($authid) {
            my $auth = $this->_authProvider($authid);
            if ($auth->enabled && !$auth->useDefaultLogin) {
                return $auth->initiateLogin(_packRequest($session));
            }
        }

        # Respond with a 401 with an appropriate WWW-Authenticate
        # that won't be snatched by the browser, but can be used
        # by JS to generate login info.
        $response->header(
            -status           => 200,
            -WWW_Authenticate => 'FoswikiBasic realm="'
              . ( $Foswiki::cfg{AuthRealm} || "" ) . '"'
        );

        $query->param(
            -name  => 'foswiki_origin',
            -value => _packRequest($session)
        );

        # Throw back the login page with the 401
        $this->login( $query, $session );
        return 1;
    }

    return 0;
}

sub loginUrl {
    my $this    = shift;
    my $session = $this->{session};
    my $topic   = $session->{topicName};
    my $web     = $session->{webName};
    return $session->getScriptUrl( 0, 'login', $web, $topic,
        foswiki_origin => _packRequest($session) );
}

sub _loadTemplate {
    my $this = shift;
    my $tmpls = $this->{session}->templates;
    $this->{tmpls} = $tmpls;
    return $tmpls->readTemplate('uauth');
}

=begin TML

---++ ObjectMethod login( $query, $session )

If a login name and password have been passed in the query, it
validates these and if authentic, redirects to the original
script. If there is no username in the query or the username/password is
invalid (validate returns non-zero) then it prompts again.

If a flag to remember the login has been passed in the query, then the
corresponding session variable will be set. This will result in the
login cookie being preserved across browser sessions.

The password handler is expected to return a perl true value if the password
is valid. This return value is stored in a session variable called
VALIDATION. This is so that password handlers can return extra information
about the user, such as a list of Wiki groups stored in a separate
database, that can then be displayed by referring to
%<nop>SESSION_VARIABLE{"VALIDATION"}%

=cut

sub login {
    my ( $this, $query, $session ) = @_;
    my $users = $session->{users};

    my (@errors, @banners);

    my $cgis = $session->getCGISession();
    my $provider;
    $provider = $query->param('uauth_provider');
    $provider = $cgis->param('uauth_provider') if $cgis && $provider;

    my @providers;
    push @providers, $provider if $provider;
    push @providers, keys %{$Foswiki::cfg{UnifiedAuth}{Providers}} unless $provider;
    push @providers, '__baseuser';
    push @providers, '__default';
    @providers = map {$this->_authProvider($_)} @providers;

    my @enabledProvider = grep {$_ if $_->enabled} @providers;
    my @earlyProvider = grep {$_ if $_->isEarlyLogin} @enabledProvider;

    foreach my $p (@earlyProvider) {
        if ($p->isMyLogin) {
            my $result = $this->processProviderLogin($query, $session, $p);
            return $result if defined $result;
        }
    }

    my $external = $query->param('uauth_external') || 0;

    foreach my $p (@enabledProvider) {
        $provider = $p;
        if (!$provider->isEarlyLogin && $provider->isMyLogin) {
            my $result = $this->processProviderLogin($query, $session, $provider);
            return $result if defined $result;
        }
    }

    my $uauth_provider = $query->param('uauth_provider');
    if($external && $uauth_provider) {
        $provider = $this->_authProvider($uauth_provider);

        return $provider->initiateExternalLogin if $external && $provider->can('initiateExternalLogin');
        return $provider->initiateLogin($query->param('foswiki_origin'));

    }

    $session->{request}->delete('validation_key');
    if (my $forceauthid = $session->{request}->param('uauth_force_provider')) {
        if (!exists $Foswiki::cfg{UnifiedAuth}{Providers}{$forceauthid}) {
            die "Invalid authentication source requested";
        }
        my $auth = $this->_authProvider($forceauthid);
        return $auth->initiateLogin(_packRequest($session));
    }

    if (my $authid = $Foswiki::cfg{UnifiedAuth}{DefaultAuthProvider}) {
        my $auth = $this->_authProvider($authid);
        return $auth->initiateLogin(_packRequest($session)) unless $auth->useDefaultLogin();
    }

    # render default dialog
    return $this->_authProvider('__default')->initiateLogin(_packRequest($session));

}

sub loadSession {
    my $this = shift;

    my $session = $this->{session};
    my $req = $session->{request};
    my $logout = $session && $req && $req->param('logout');
    my $user = $this->SUPER::loadSession(@_);
    my $cgis = $session->getCGISession(); # note: might not exist (eg. call from cli)

    my $bu = \%Foswiki::Users::BaseUserMapping::BASE_USERS;
    my $cuids = \%Foswiki::UnifiedAuth::Providers::BaseUser::CUIDs;
    foreach my $base (keys %$bu) {
        my $login = $bu->{$base}{login};
        my $wn = $bu->{$base}{wikiname};
        $session->{users}->{login2cUID}->{$login} = $cuids->{$base};
        $session->{users}->{wikiName2cUID}->{$wn} = $cuids->{$base};
    }

    if ($logout) {
        if ($cgis) {
            $cgis->clear(['uauth_provider']);
            $cgis->clear(['uauth_state']);
        }

        while (my ($id, $hash) = each %{$Foswiki::cfg{UnifiedAuth}{Providers}}) {
            my $mod = $hash->{module};
            next unless $mod;
            my $provider = $this->_authProvider($id);
            if($provider->can('handleLogout')) {
                $provider->handleLogout($session, $user);
            }
        }
    }

    if(Foswiki::Func::isAnAdmin($user) && (my $refresh = $req->param('refreshauth'))) {
        $req->delete('refreshauth');
        if($refresh eq 'all') {
            Foswiki::Func::writeWarning("refreshing all providers");
            foreach my $id ( ('__baseuser', sort(keys %{$Foswiki::cfg{UnifiedAuth}{Providers}}), '__uauth' ) ) {
                Foswiki::Func::writeWarning("refreshing $id");
                try {
                    my $provider = $this->_authProvider($id);
                    $provider->refresh() if $provider;
                } catch Error::Simple with {
                    Foswiki::Func::writeWarning(shift);
                };
            }
        } elsif ((defined $Foswiki::cfg{UnifiedAuth}{Providers}{$refresh}) || $refresh eq '__uauth') {
            my $provider = $this->_authProvider($refresh);
            $provider->refresh() if $provider;
        }
        # dump the db for backup solutions
        unless ( $Foswiki::cfg{UnifiedAuth}{NoDump} ) {
            my $dumpcmd = $Foswiki::cfg{UnifiedAuth}{DumpCommand} || 'pg_dump foswiki_users';
            my ($output, $exit, $stderr) = Foswiki::Sandbox->sysCommand(
                $dumpcmd
            );
            if($exit) {
                $stderr = '' unless defined $stderr;
                Foswiki::Func::writeWarning("Error while dumping foswiki_users: $exit\n$output\n$stderr");
            } else {
                my $dir = Foswiki::Func::getWorkArea('UnifiedAuth');
                Foswiki::Func::saveFile("$dir/foswiki_users.dump", $output);
            }
        }
    }

    if ($cgis && $cgis->param('force_set_pw') && $req) {
        my $topic  = $session->{topicName};
        my $web    = $session->{webName};
        unless( $req->param('resetpw')) {
            unless( $topic eq $Foswiki::cfg{HomeTopicName} && $web eq $Foswiki::cfg{SystemWebName}) {
                my $url = Foswiki::Func::getScriptUrl($Foswiki::cfg{SystemWebName},
                               'ChangePassword',
                               'oops',
                               template => 'oopsresetpassword',
                               resetpw => '1');
                Foswiki::Func::redirectCgiQuery( undef, $url);
            }
        }
    }
    return $user;
}

sub processProviderLogin {
    my ($this, $query, $session, $provider) = @_;

    my $context = Foswiki::Func::getContext();
    my $topic  = $session->{topicName};
    my $web    = $session->{webName};

    my $loginResult;
    my $error = '';
    eval {
        $loginResult = $provider->processLogin();
        if ($loginResult && $loginResult eq 'wait for next step') { # XXX it would be better to return a hash with a status
            Foswiki::Func::writeWarning("Waiting for client to get back to us.") if defined $provider->{config}->{debug} && $provider->{config}->{debug} eq 'verbose';
            undef $loginResult;
        } elsif ($loginResult && $provider->{config}->{identityProvider}) {
            my $id_provider = $provider->{config}->{identityProvider};
            my $providersResult;
            if ($id_provider eq '_all_') {
                $this->{uac} = Foswiki::UnifiedAuth->new unless $this->{uac};
                ($id_provider) = $this->{uac}->getProviderForUser($loginResult);
                $id_provider ||= '__default';
            }
            my $identity = $this->_authProvider($id_provider);
            if ($identity->isa('Foswiki::UnifiedAuth::IdentityProvider')) {
                $providersResult = $identity->identify($loginResult);
            }
            if($providersResult) {
                $loginResult = $providersResult;
            } else {
                if($provider->{config}->{debug}) {
                    Foswiki::Func::writeWarning("Login '$loginResult' supplied by '$provider->{id}' could not be found in identity provider '$provider->{config}->{identityProvider}'"); # do not use $id_provider, because it might have been _all_
                    $error = $session->i18n->maketext("Your user account is not configured for the authentication with this wiki. Please contact your administrator for further assistance.");
                }
                undef $loginResult;
            }
        }
    };
    if ($@) {
        $error = $@;
        if (ref($@) && $@->isa("Error")) {
            $error = $@->text if ref($@) && $@->isa("Error");
        } else {
            Foswiki::Func::writeWarning($error);
        }
    }

    if (ref($loginResult) eq 'HASH' && $loginResult->{cuid}) {
        my $deactivated = $this->{uac}->{db}->selectrow_array("SELECT deactivated FROM users WHERE cuid=?", {}, $loginResult->{cuid});
        unless ($deactivated) {
            $this->userLoggedIn($loginResult->{cuid});
            $session->logger->log(
                {
                    level    => 'info',
                    action   => 'login',
                    webTopic => $web . '.' . $topic,
                    extra    => "AUTHENTICATION SUCCESS - $loginResult->{cuid} - "
                }
            );
            $this->{_cgisession}->param( 'VALIDATION', encode_json($loginResult->{data} || {}) )
              if $this->{_cgisession};
            my ( $origurl, $origmethod, $origaction ) = _unpackRequest($provider->origin);
            if (!$origurl || $origaction eq 'login') {
                $origurl = $session->getScriptUrl(0, 'view', $web, $topic);
                $session->{request}->delete_all;
            } else {
                # Unpack params encoded in the origurl and restore them
                # to the query. If they were left in the query string they
                # would be lost if we redirect with passthrough.
                # First extract the params, ignoring any trailing fragment.
                if ( $origurl =~ s/\?([^#]*)// ) {
                    foreach my $pair ( split( /[&;]/, $1 ) ) {
                        if ( $pair =~ /(.*?)=(.*)/ ) {
                            $session->{request}->param( $1, TAINT($2) );
                        }
                    }
                }

                # Restore the action too
                $session->{request}->action($origaction) if $origaction;
            }
            $session->{request}->method($origmethod);
            $session->redirect($origurl, 1);
            return $loginResult->{cuid};
        }
    }

    if ($Foswiki::cfg{UnifiedAuth}{DefaultAuthProvider}) {
        $context->{uauth_failed_nochoose} = 1;
    }

    # $session->{response}->status(200);
    $session->logger->log(
        {
            level    => 'info',
            action   => 'login',
            webTopic => $web . '.' . $topic,
            extra    => "AUTHENTICATION FAILURE",
        }
    );

    my $tmpl = $this->_loadTemplate;
    my $banner = '';
    $banner = $this->{tmpls}->expandTemplate('AUTH_FAILURE');

    if($error eq '') {
        $error = $session->i18n->maketext("Wrong username or password"); # XXX this is in many cases not true, it would be better if providers passed down a message
    }
    $session->{prefs}->setSessionPreferences(UAUTH_AUTH_FAILURE_MESSAGE => $error, BANNER => $banner);

    return undef;
}

# Like the super method, but checks if the topic exists (to avoid dead links).
sub _LOGOUTURL {
    my ( $session, $params, $topic, $web ) = @_;
    my $this = $session->getLoginManager();

    my $logoutWeb = $session->{prefs}->getPreference('BASEWEB');
    my $logoutTopic = $session->{prefs}->getPreference('BASETOPIC');
    unless(Foswiki::Func::topicExists($logoutWeb, $logoutTopic)) {
        $logoutWeb = $Foswiki::cfg{UsersWebName};
        $logoutTopic = $Foswiki::cfg{HomeTopicName};
    }

    return $session->getScriptUrl(
        0, 'view',
        $logoutWeb,
        $logoutTopic,
        'logout' => 1
    );
}

# Unmodified from super method, however we need to copy it, so we can use the
# modified _LOGOUTURL.
sub _LOGOUT {
    my ( $session, $params, $topic, $web ) = @_;
    my $this = $session->getLoginManager();

    return '' unless $session->inContext('authenticated');

    my $url = _LOGOUTURL(@_);
    if ($url) {
        my $text = $session->templates->expandTemplate('LOG_OUT');
        return CGI::a( { href => $url }, $text );
    }
    return '';
}

1;
__END__
Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2014 Foswiki Contributors. All Rights Reserved.
Foswiki Contributors are listed in the AUTHORS file in the root
of this distribution. NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 2005-2006 TWiki Contributors. All Rights Reserved.
Copyright (C) 2005 Greg Abbas, twiki@abbas.org

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

