# Module of Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2012 Jan Krueger, Modell Aachen GmbH
# http://modell-aachen.de/
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
package Foswiki::LoginManager::SwitchableLogin;

=begin TML

---+ Foswiki::LoginManager::SwitchableLogin

This is a simple login manager that adds the ability for admins to switch to
an an arbitrary user (for testing permissions etc.) on top of a real login
manager.

=cut

use strict;
use Assert ();
use Foswiki::LoginManager ();
use Foswiki::Sandbox ();

our @ISA;

use constant CGIDRIVER => 'driver:File;serializer:Storable';

=begin TML

---++ ClassMethod new($session)

Construct the <nop>SwitchableLogin object

=cut

sub new {
    my ($class, $session) = @_;

    my $base = $Foswiki::cfg{SwitchableLoginManagerContrib}{ActualLoginManager};
    # Prevent infinite recursion
    $base = 'Foswiki::LoginManager' if !$base || $base eq 'Foswiki::LoginManager::SwitchableLogin';

    # Magically make the desired actual login manager our base class
    eval "require $base";
    die $@ if $@;
    @ISA = ($base);

    bless( $class->SUPER::new($session), $class );
}

=begin TML

---++ ObjectMethod getUser()

Returns the user from the web server (if any)... but, more interestingly,
overrides this with our sudo mechanism if applicable.

=cut

sub getUser {
    my $this = shift;
    my $session = $this->{session};

    my $webserverUser = $this->SUPER::getUser();
    return $webserverUser if $ENV{NO_FOSWIKI_SESSION};

    # SMELL: we need to copy some code from LoginManager here because we can't
    # hook into the original code in the right place :(

    if ( $Foswiki::cfg{UseClientSessions}
        && !$session->inContext('command_line') )
    {

        $this->{_haveCookie} = $session->{request}->header('Cookie');
        my $sessionDir = "$Foswiki::cfg{WorkingDir}/tmp";

        # First, see if there is a cookied session, creating a new session
        # if necessary.
        if ( $Foswiki::cfg{Sessions}{MapIP2SID} ) {

            # map the end user IP address to a session ID

            my $sid = $this->_IP2SID();
            if ($sid) {
                $this->{_cgisession} =
                  Foswiki::LoginManager::Session->new( CGIDRIVER, $sid,
                    { Directory => $sessionDir } );
            }
            else {

                # The IP address was not mapped; create a new session

                $this->{_cgisession} =
                  Foswiki::LoginManager::Session->new( CGIDRIVER, undef,
                    { Directory => $sessionDir } );
                $this->_IP2SID( $this->{_cgisession}->id() );
            }
        }
        else {

            # IP mapping is off; use the request cookie

            $this->{_cgisession} = Foswiki::LoginManager::Session->new(
                CGIDRIVER,
                $session->{request},
                { Directory => $sessionDir }
              );
        }

        die Foswiki::LoginManager::Session->errstr()
          unless $this->{_cgisession};


        # It's sudo time! (maybe)
        unless ($Foswiki::cfg{SwitchableLoginManagerContrib}{SudoEnabled} &&
            $Foswiki::cfg{SwitchableLoginManagerContrib}{SudoAuth} ne 'changeme!'
        ) {
            return $webserverUser;
        }

        my $sessionUser = Foswiki::Sandbox::untaintUnchecked(
            $this->{_cgisession}->param('SUDOTOAUTHUSER') );
        my $realSessionUser = Foswiki::Sandbox::untaintUnchecked(
            $this->{_cgisession}->param('AUTHUSER') );

        my $sudo = $session->{request}->param('sudouser');
        # "Authentication" as legitimate sudo request
        my $sudoauth = $session->{request}->param('sudoauth');
        my $orig = $this->{_cgisession}->param('SUDOFROMAUTHUSER') || $realSessionUser;

        unless (defined $sudo &&
            ($realSessionUser eq $Foswiki::cfg{AdminUserLogin} || defined($orig) && $orig eq $this->{_cgisession}->param('SUDOALLOW')) &&
            (!$sudo || $sudoauth eq $Foswiki::cfg{SwitchableLoginManagerContrib}{SudoAuth})
        ) {
            return $sessionUser || $webserverUser;
        }
        my $authUser;

        # Un-sudo 'em
        if (!$sudo) {
            $this->{_cgisession}->param('AUTHUSER', $orig);
            $this->{_cgisession}->clear(['SUDOFROMAUTHUSER', 'SUDOTOAUTHUSER']);
            $authUser = $orig;
            Foswiki::Func::writeDebug("unsudo: $orig <- $realSessionUser");
        }
        else {
            $this->{_cgisession}->param('SUDOFROMAUTHUSER', $orig);
            $this->{_cgisession}->param('SUDOTOAUTHUSER', $sudo);
            # It's hard to reliably check admin rights for the raw user ID
            # this early in the session, so we whitelist them once they have
            # managed to get here via the internal admin login feature.
            $this->{_cgisession}->param('SUDOALLOW', $orig);
            $authUser = $sudo;
            Foswiki::Func::writeDebug("sudo: $orig -> $sudo");
        }
        $session->{request}->delete('sudouser');
        $session->{request}->delete('sudoauth');
        my $pretendUser = $authUser || $sessionUser || $webserverUser;
        $this->{_cgisession}->param('AUTHUSER', $pretendUser);
        $this->{_cgisession}->flush;
        return $pretendUser;
    }
    return $webserverUser;
}

1;
