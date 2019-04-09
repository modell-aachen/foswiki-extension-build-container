package Foswiki::UnifiedAuth::Providers::BaseUser;

use strict;
use warnings;

use DBI;
use Encode;
use Error;
use JSON;

use Foswiki::Func;
use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::Provider;
use Foswiki::Users::BaseUserMapping;

our @ISA = qw(Foswiki::UnifiedAuth::Provider);

Foswiki::Users::BaseUserMapping->new($Foswiki::Plugins::SESSION) if $Foswiki::Plugins::SESSION;
my $bu = \%Foswiki::Users::BaseUserMapping::BASE_USERS;

our %CUIDs = (
    BaseUserMapping_111 => 'aafd6652-3181-4845-b615-4bb7b970ca69',
    BaseUserMapping_222 => 'dc9f6b91-3762-4343-89e6-5d0795e85805',
    BaseUserMapping_333 => '3abfa98b-f92b-42ab-986e-872abca52a49',
    BaseUserMapping_666 => '09c180b0-fc8b-4f2c-a378-c09ccf6fb9f9',
    BaseUserMapping_999 => '40dda76a-1207-400f-b234-69da71ac405b'
);

# XXX note: %pid% and %id% must be hacked out when applying
my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_baseuser (
            cuid UUID NOT NULL,
            info JSONB NOT NULL,
            PRIMARY KEY (cuid)
        )",
        "INSERT INTO users_baseuser (cuid, info)
            VALUES
                ('$CUIDs{BaseUserMapping_111}', '{\"wikiname\": \"$bu->{BaseUserMapping_111}{wikiname}\", \"description\": \"Project Contributor\"}'),
                ('$CUIDs{BaseUserMapping_222}', '{\"wikiname\": \"$bu->{BaseUserMapping_222}{wikiname}\", \"description\": \"Registration Agent\"}'),
                ('$CUIDs{BaseUserMapping_333}', '{\"wikiname\": \"$bu->{BaseUserMapping_333}{wikiname}\", \"description\": \"Internal Admin User\", \"email\": \"$bu->{BaseUserMapping_333}{email}\"}'),
                ('$CUIDs{BaseUserMapping_666}', '{\"wikiname\": \"$bu->{BaseUserMapping_666}{wikiname}\", \"description\": \"Guest User\"}'),
                ('$CUIDs{BaseUserMapping_999}', '{\"wikiname\": \"$bu->{BaseUserMapping_999}{wikiname}\", \"description\": \"Unknown User\"}')",
        "INSERT INTO meta (type, version) VALUES('users_baseuser', 0)",
        "INSERT INTO providers (pid, name) VALUES('%pid%', '%id%')",
        "INSERT INTO users (cuid, pid, login_name, wiki_name, display_name, email)
            VALUES
                ('$CUIDs{BaseUserMapping_111}', '%pid%', '$bu->{BaseUserMapping_111}{login}', '$bu->{BaseUserMapping_111}{wikiname}', 'Project Contributor', ''),
                ('$CUIDs{BaseUserMapping_222}', '%pid%', '$bu->{BaseUserMapping_222}{login}', '$bu->{BaseUserMapping_222}{wikiname}', 'Registration Agent', ''),
                ('$CUIDs{BaseUserMapping_333}', '%pid%', '$bu->{BaseUserMapping_333}{login}', '$bu->{BaseUserMapping_333}{wikiname}', 'Internal Admin User', '$bu->{BaseUserMapping_333}{email}'),
                ('$CUIDs{BaseUserMapping_666}', '%pid%', '$bu->{BaseUserMapping_666}{login}', '$bu->{BaseUserMapping_666}{wikiname}', 'Guest User', ''),
                ('$CUIDs{BaseUserMapping_999}', '%pid%', '$bu->{BaseUserMapping_999}{login}', '$bu->{BaseUserMapping_999}{wikiname}', 'Unknown User', '')",
        "INSERT INTO merged_users (primary_cuid, mapped_cuid, primary_provider, mapped_provider)
            VALUES
                ('$CUIDs{BaseUserMapping_111}', '$CUIDs{BaseUserMapping_111}', '%pid%', '%pid%'),
                ('$CUIDs{BaseUserMapping_222}', '$CUIDs{BaseUserMapping_222}', '%pid%', '%pid%'),
                ('$CUIDs{BaseUserMapping_333}', '$CUIDs{BaseUserMapping_333}', '%pid%', '%pid%'),
                ('$CUIDs{BaseUserMapping_666}', '$CUIDs{BaseUserMapping_666}', '%pid%', '%pid%'),
                ('$CUIDs{BaseUserMapping_999}', '$CUIDs{BaseUserMapping_999}', '%pid%', '%pid%')"
    ]
);

sub isAdminUser {
    my ($user) = @_;

    return 0 unless defined $user;

    return 1 if $user eq $bu->{BaseUserMapping_333}{login} || $user eq 'BaseUserMapping_333' || $user eq $CUIDs{BaseUserMapping_333};
    return 0;
}

sub getBaseUserCUID {
    return $CUIDs{shift};
}

sub getAdminCuid {
    return $CUIDs{BaseUserMapping_333};
}

sub new {
    my ($class, $session, $id, $config) = @_;
    my $this = $class->SUPER::new($session, $id, $config);
    return $this;
}

sub enabled {
    1;
}

sub initiateLogin {
    my ($this, $origin) = @_;
    my $state = $this->SUPER::initiateLogin($origin);
    return $state;
}

sub useDefaultLogin {
    1;
}

# Only checks database schema. BaseUsers are fixed and do not need re-indexing.
# When a cuid is passed in, only delegate to super class.
sub refresh {
    my $this = shift;
    my $cuid = shift;

    return $this->SUPER::refresh($cuid) if $cuid;

    my $uauth = Foswiki::UnifiedAuth->new();
    my $pid = $this->getPid();
    my @pid_schema_updates = @schema_updates;
    foreach my $a ( @pid_schema_updates ) {
        $a = [ map { $_ =~ s#\%id\%#$this->{id}#gr =~ s#\%pid\%#$pid#gr } @$a];
    }
    $uauth->apply_schema('users_baseuser', @pid_schema_updates);
    return $this->SUPER::refresh();
}

sub processLoginData {
    my ($this, $user, $pass) = @_;
    my $result = $this->checkPassword($user, $pass);
    return undef unless $result;

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;
    my $provider = $db->selectrow_hashref("SELECT * FROM providers WHERE name=?", {}, $this->{id});
    my $userdata = $db->selectrow_hashref("SELECT * FROM users AS u NATURAL JOIN users_baseuser WHERE u.login_name=? AND u.pid=?", {}, $user, $provider->{pid});
    return {
        cuid => $userdata->{cuid},
        data => {}
    };
}

sub checkPassword {
    my ( $this, $login, $pass ) = @_;
    return 0 unless $login eq $Foswiki::cfg{AdminUserLogin};

    # All of the digest / hash routines require bytes
    $pass = Encode::encode_utf8($pass);
    my $hash = $Foswiki::cfg{Password};

    if ($hash) {
        if (length($hash) == 13) {
            return 1 if (crypt($pass, $hash) eq $hash);
        } elsif (length($hash) == 42) {
            my $salt = substr($hash, 0, 10);
            return 1 if ($salt . Digest::MD5::md5_hex($salt . $pass) eq $hash);
        } else {
            my $salt = substr($hash, 0, 14);
            return 1 if (Crypt::PasswdMD5::apache_md5_crypt( $pass, $salt ) eq $hash);
        }
    }

    # be a little more helpful to the admin
    if ( $login eq $Foswiki::cfg{AdminUserLogin} && !$hash ) {
     $this->{error} =
       'To login as ' . $login . ', you must set {Password} in configure.';
    }

    return 0;
}

1;
