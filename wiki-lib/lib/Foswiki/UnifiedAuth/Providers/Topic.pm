package Foswiki::UnifiedAuth::Providers::Topic;

use Error;
use JSON;
use Net::CIDR;
use Crypt::PBKDF2;
use Error ':try';
use Error::Simple;

use strict;
use warnings;

use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
use Foswiki::Users::TopicUserMapping;
use Foswiki::Users::UnifiedAuthUser;
use Foswiki::Users::HtPasswdUser;
our @ISA = qw(Foswiki::UnifiedAuth::Provider);

my @schema_updates = (
    [
        "INSERT INTO meta (type, version) VALUES('providers_topic', 0)",
        "INSERT INTO providers (name) VALUES('topic')",
    ]
);

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    # XXX no finish
    my $implPasswordManager = $this->{config}->{PasswordManager} || 'Foswiki::Users::UnifiedAuthUser';
    $implPasswordManager = 'Foswiki::Users::Password'
      if ( $implPasswordManager eq 'none' );
    eval "require $implPasswordManager";
    die $@ if $@;
    $this->{passwords} = $implPasswordManager->new($session);

    unless ( $this->{passwords}->readOnly() ) {
        $this->{session}->enterContext('passwords_modifyable');
    }

    return $this;
}

sub supportsRegistration {
    1; # TODO: check if PasswordManager allows registration
}

sub useDefaultLogin {
    1;
}

sub _generatePwHash {
    my $password = shift;

    my $pbkdf2 = Crypt::PBKDF2->new(
        hash_class => 'HMACSHA2',
        hash_args => {
            sha_size => 512,
        },
        iterations => 10000,
        salt_len => 10,
    );
    return $pbkdf2->generate($password);
}

sub rndStr{
    my $strLength = shift;
    my @classes = @_;
    join '', @classes[ map{ rand @classes } 1 .. $strLength ];
}

sub generateResetId {
    my $random = rndStr(20, 'A'..'Z', 0..9, 'a'..'z' );
    return $random;
}


sub setPassword {
    my ( $this, $login, $newUserPassword, $oldUserPassword ) = @_;

    if ( defined($oldUserPassword) ) {
        unless ( $oldUserPassword eq '1' ) {
            return undef unless $this->checkPassword( $login, $oldUserPassword );
        }
    }
    elsif ( $this->fetchPass($login) ) {
        $this->{error} = $login . ' already exists';
        return 0;
    }

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $userinfo = $db->selectrow_hashref("SELECT * FROM users WHERE users.login_name=?", {}, $login);
    # XXX UTF-8
    my $pwHash;
    if ($newUserPassword) {
        $pwHash = _generatePwHash($newUserPassword);
    }
    my $cuid = $uauth->update_user('UTF-8', $userinfo->{cuid}, {
        password => $pwHash
    });
    my $cgis = $this->{session}->getCGISession();
    $cgis->param('force_set_pw', 0);
    $uauth->update_reset_request('UTF-8', $userinfo->{cuid}, undef, undef);

    $this->{error} = undef;
    return 1;
}

# When this is __uauth: Refresh all groups
# When this is a regular topic provider: Refresh all users unless a cuid is
#    provided
# When a cuid is provided: Only delegate to super class
sub refresh {
    my ( $this, $cuid ) = @_;

    return $this->SUPER::refresh($cuid) if $cuid;

    my $pid = $this->getPid();
    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my @addUsers = ();

    # import existing groups
    # This is not terribly efficient, however those groups should not be
    # terribly big.
    if($this->{id} eq '__uauth') {
        my $oldGroups = { map { $_ => 1 } @{ $db->selectcol_arrayref("SELECT name FROM groups WHERE pid=?", {}, $pid) } };

        foreach my $topic ( Foswiki::Func::getTopicList($Foswiki::cfg{UsersWebName}) ) {
            next unless $topic =~ m#Group$#;
            my ($meta) = Foswiki::Func::readTopic($Foswiki::cfg{UsersWebName}, $topic);
            my $pref = $meta->get('PREFERENCE', 'GROUP');
            next unless $pref;
            my @entries = map{ $_ =~ s#^\s*##r =~ s#\s*$##r } split(/,/, $pref->{value} || '');
            my @users = ();
            my @nested = ();
            foreach my $entry ( @entries ) {
                my $cuid = $uauth->getCUID($entry);
                unless($cuid) {
                    Foswiki::Func::writeWarning("Could not import user $entry to group $topic");
                    next;
                }
                if(Foswiki::Func::isGroup($entry)) {
                    push @nested, $cuid;
                } else {
                    push @users, $cuid;
                }
            }
            $uauth->updateGroup($pid, $topic, \@users, \@nested);
            delete $oldGroups->{$topic};
        }

        foreach my $oldGroup ( keys %$oldGroups ) {
            $uauth->removeGroup( name => $oldGroup, pid => $pid );
        }

        # do not import any users into __uauth
        return $this->SUPER::refresh();
    }

    # Faking HtPasswdUser, so we get the correct wikiname and email from the
    # UserMapper.
    # XXX: If we do not find the user in WikiUsers, it will simply generate a
    # new WikiName.
    {
        unless (-f $Foswiki::cfg{Htpasswd}{FileName}) {
            my $msg = <<MSG;
Unable to find '.htpasswd' file at '$Foswiki::cfg{Htpasswd}{FileName}'.
Importing users from old TopicUserMapping will probably fail!
MSG
            print STDERR "$msg\n" if $Foswiki::engine->isa('Foswiki::Engine::CLI');
            Foswiki::Func::writeWarning($msg);
        }

        local $Foswiki::cfg{PasswordManager} = 'Foswiki::Users::HtPasswdUser';
        my $topicMapping = Foswiki::Users::TopicUserMapping->new($this->{session});

        my $topicPwManager = Foswiki::Users::HtPasswdUser->new($this->{session});
        if( $topicPwManager->canFetchUsers() ) {
            my $iter = $topicPwManager->fetchUsers();
            while ( $iter->hasNext() ) {
                my $login = $iter->next();
                # XXX
                my $cuid = $db->selectrow_array("SELECT cuid FROM users WHERE users.login_name=? AND users.pid=?", {}, $login, $pid);
                unless($cuid) {
                    #Import user
                    $cuid = $topicMapping->login2cUID($login);
                    my $wikiname = $topicMapping->getWikiName($cuid);
                    my @emails = $topicPwManager->getEmails($login);
                    if($Foswiki::UNICODE) {
                        $login = Foswiki::encode_utf8($login);
                        $wikiname = Foswiki::encode_utf8($wikiname);
                        @emails = map {Foswiki::encode_utf8($_)} @emails;
                    }
                    if($wikiname && @emails) {
                        push @addUsers, [$login, $wikiname, \@emails];
                    } else {
                        Foswiki::Func::writeWarning("Error importing user $login: could not determine email or wikiname");
                    }
                }
            }
        }
    }
    foreach my $addUser ( @addUsers ) {
        try {
            $this->addUser($addUser->[0], $addUser->[1], undef, $addUser->[2], 1);
        } catch Error::Simple with {
            Foswiki::Func::writeWarning(shift);
        };
    }

    return $this->SUPER::refresh();
}

sub addUser {
    my ( $this, $login, $wikiname, $password, $emails, $import ) = @_;

    # XXX not thread save
    # TODO: be transactional
    my $auth = Foswiki::UnifiedAuth->new();
    my $cuid;
    my $usedBy = $this->{session}->{users}->findUserByWikiName($wikiname);
    if($usedBy && scalar @$usedBy) {
        throw Error::Simple("Failed to add user: WikiName ($wikiname) already in use by: ".join(', ', @$usedBy));
    }
    $usedBy = $this->{session}->{users}->getLoginName($login);
    if($usedBy) {
        throw Error::Simple("Failed to add user: login ($login) already in use by $usedBy");
    }

    my $pid = $this->getPid();
    unless($pid) {
        throw Error::Simple("Failed to add user: TopicUserMapping mal-configured (could not get pid)");
    }

    if(ref $emails eq 'ARRAY') {
        $emails = $emails->[0];
    }
    unless($emails) {
        throw Error::Simple("Failed to add user: No email given for $wikiname");
    }
    ($cuid, undef, my $error) = $this->_checkPassword($login, $password);
    return $cuid if $cuid;
    if ($error && $error ne 'notFound') {
        # They exist; their password must match
        throw Error::Simple(
            $this->{session}->i18n->maketext(
                'User exists in the Password Manager,  and the password you provided is different from the users current password.   You cannot add a user and change the password at the same time.'
            )
        );
    } else {
        # add a new user

        unless ( defined($password) ) {
            require Foswiki::Users;
            $password = Foswiki::Users::randomPassword();
        }

        if(ref $emails eq 'ARRAY') {
            $emails = $emails->[0];
        }
        # XXX UTF-8
        my $pwHash;
        if (!$import && $password) {
            $pwHash = _generatePwHash($password);
        }
        $cuid = $auth->add_user('UTF-8', $pid, {
            email => $emails,
            login_name => $login,
            wiki_name => $wikiname,
            display_name => $wikiname,
            password => $pwHash
        });

        my $addedWikiName = $this->{session}->{users}->getWikiName($cuid);
        unless($addedWikiName eq $wikiname) {
            $auth->delete_user($cuid);
            throw Error::Simple("Failed to add user: WikiName ($wikiname) already in use");
        }
    }

    return $cuid;
}

sub processLoginData {

    my ( $this, $login, $password ) = @_;

    my ($cuid, $change_password) = $this->_checkPassword($login, $password);
    return undef unless $cuid;

    if($change_password) {
        my $cgis = $this->{session}->getCGISession();
        $cgis->param('force_set_pw', 1);
    }

    return { cuid => $cuid, data => {} };
}

# Validates password and user for _this provider_.
#
#    * Will return the cuid, if the password check passed (htpasswd or db)
#    * Will set the change_password flag, when the password could be validated
#      from the .htpasswd file only, but not from the db
#    * Will set errorCode to 'notFound' if the user does not exist in the db
#    * Will set errorCode to 'wrongPassword' if the user was found but the
#      password is wrong (htpasswd or db)
#
# returns (cuid, change_password, errorCode)
sub _checkPassword {
    my ( $this, $login, $password ) = @_;

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;

    my $pid = $this->getPid();

    my $userinfo = $db->selectrow_hashref("SELECT cuid, wiki_name, password FROM users WHERE users.login_name=? AND users.pid=?", {}, $login, $pid);
    return (undef, undef, 'notFound') unless $userinfo;
    my $change_password;
    if( $userinfo->{password} ) {
        my $pbkdf2 = Crypt::PBKDF2->new;
        return (undef, undef, 'wrongPassword') unless $pbkdf2->validate( $userinfo->{password}, $password );
    } else {
        my $topicPwManager = Foswiki::Users::HtPasswdUser->new($this->{session});
        return (undef, undef, 'wrongPassword') unless $topicPwManager->checkPassword( $login, $password );
        $change_password = 1;
    }

    return ($userinfo->{cuid}, $change_password);
}

sub checkPassword {
    my ( $this, $login, $password ) = @_;

    my ($cuid) = $this->_checkPassword($login, $password);
    return ($cuid) ? 1 : undef;
}

1;

