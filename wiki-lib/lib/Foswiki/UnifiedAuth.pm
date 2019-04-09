package Foswiki::UnifiedAuth;

use strict;
use warnings;
use utf8;

use DBI;
use Encode;

use Foswiki::Contrib::PostgreContrib;
use Data::GUID;

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS meta (type TEXT NOT NULL UNIQUE, version INT NOT NULL)",
        "INSERT INTO meta (type, version) VALUES('core', 0)",
        "CREATE TABLE IF NOT EXISTS providers (
            pid SERIAL,
            name TEXT NOT NULL,
            enabled INTEGER DEFAULT 1,
            invisible INTEGER DEFAULT 0
        )",
        "CREATE TABLE IF NOT EXISTS users (
            cuid UUID NOT NULL PRIMARY KEY,
            pid INTEGER NOT NULL,
            login_name TEXT NOT NULL,
            wiki_name TEXT NOT NULL,
            display_name TEXT NOT NULL,
            email TEXT NOT NULL,
            password CHAR(135),
            deactivated INTEGER DEFAULT 0
        )",
        "CREATE UNIQUE INDEX idx_wiki_name ON users (wiki_name)",
        "CREATE UNIQUE INDEX idx_cuid ON users (cuid)",
        "CREATE INDEX idx_login_name ON users (login_name)",
        "CREATE INDEX idx_email ON users (email)",
        "CREATE INDEX idx_deactivated ON users (deactivated)",
        "CREATE TABLE IF NOT EXISTS merged_users (
            primary_cuid UUID NOT NULL,
            mapped_cuid UUID NOT NULL,
            primary_provider INTEGER NOT NULL,
            mapped_provider INTEGER NOT NULL
        )",
        "CREATE UNIQUE INDEX idx_primary_cuid ON merged_users (primary_cuid)",
        "CREATE UNIQUE INDEX idx_mapped_cuid ON merged_users (mapped_cuid)",
        "CREATE TABLE IF NOT EXISTS groups (
            cuid UUID NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            pid INTEGER NOT NULL
        )",
        "CREATE INDEX idx_groups ON groups (name)",
        "CREATE TABLE IF NOT EXISTS group_members (
            g_cuid UUID NOT NULL,
            u_cuid UUID NOT NULL,
            PRIMARY KEY (g_cuid, u_cuid)
        )",
        "CREATE INDEX idx_group_cuid ON group_members (g_cuid)",
        "CREATE INDEX idx_member_cuid ON group_members (u_cuid)",
        "CREATE TABLE IF NOT EXISTS nested_groups (
            parent UUID NOT NULL,
            child UUID NOT NULL,
            PRIMARY KEY (parent, child)
        )"
    ],
    [
        "ALTER TABLE users ADD COLUMN reset_id Char(20), ADD COLUMN reset_limit INTEGER",
        "UPDATE meta SET version=1 WHERE type='core'"
    ], [
        "ALTER TABLE IF EXISTS users ADD COLUMN uac_disabled INTEGER DEFAULT 0",
        "UPDATE meta SET version=2 WHERE type='core'"
    ]
);

my $internal_cfg = {
    '__default' => { config => {}, module => 'Default' },
    '__baseuser' => { config => {}, module => 'BaseUser' },
    '__uauth' => { config => {}, module => 'Topic' },
};

my $singleton;

sub new {
    my ($class) = @_;
    return $singleton if $singleton;
    my $this = bless {}, $class;

    $singleton = $this;
}

sub finish {
    $singleton->{connection}->finish if $singleton->{connection};
    undef $singleton->{db} if $singleton;
    undef $singleton;
}

sub db {
    my $this = shift;
    $this->connect unless defined $this->{db};
    $this->{db};
}

sub connect {
    my $this = shift;
    return $this->{db} if defined $this->{db};
    my $connection = Foswiki::Contrib::PostgreContrib::getConnection('foswiki_users');
    $this->{connection} = $connection;
    $this->{db} = $connection->{db};
    $this->{schema_versions} = {};
    eval {
        $this->{schema_versions} = $this->db->selectall_hashref("SELECT * FROM meta", 'type', {});
    };
    $this->apply_schema('core', @schema_updates);
}

sub apply_schema {
    my $this = shift;
    my $type = shift;
    my $db = $this->{db};

    if (!$this->{schema_versions}{$type}) {
        $this->{schema_versions}{$type} = { version => 0 };
    }

    my $v = $this->{schema_versions}{$type}{version};
    return if $v >= @_;
    for my $schema (@_[$v..$#_]) {
        $db->begin_work;
        for my $s (@$schema) {
            if (ref($s) eq 'CODE') {
                $s->($db);
            } else {
                $db->do($s);
            }
        }

        $db->do("UPDATE meta SET version=? WHERE type=?", {}, ++$v, $type);
        $db->commit;
    }
}

my %normalizers = (
    de => sub {
        my $wn = shift;
        $wn =~ s/Ä/Ae/g;
        $wn =~ s/Ö/Oe/g;
        $wn =~ s/Ü/Ue/g;
        $wn =~ s/ä/ae/g;
        $wn =~ s/ö/oe/g;
        $wn =~ s/ü/ue/g;
        $wn =~ s/ß/ss/g;
        $wn;
    }
);

sub guid {
    my $this = shift;
    lc(Data::GUID->guid);
}

sub getCUID {
    my ($this, $user, $noUsers, $noGroups) = @_;

    my $db = $this->db;

    my $unescapedName = $user =~ s/_2d/-/gr;
    if(isCUID($unescapedName)) {
        unless ($noUsers) {
            my $fromDB = $db->selectrow_array('SELECT cuid FROM users WHERE cuid=?', {}, $unescapedName);
            return $fromDB if defined $fromDB;
        }

        unless ($noGroups) {
            my $fromDB = $db->selectrow_array('SELECT cuid FROM groups WHERE cuid=?', {}, $unescapedName);
            return $fromDB if defined $fromDB;
        }

        return undef; # not found
    }

    unless ($noUsers) {
        my $fromDB = $db->selectrow_array('SELECT cuid FROM users WHERE login_name=? OR wiki_name=?', {}, $user, $user);
        return $fromDB if defined $fromDB;
    }

    unless ($noGroups) {
        my $fromDB = $db->selectrow_array('SELECT cuid FROM groups WHERE name=?', {}, $user);

        return $fromDB if defined $fromDB;
    }

    return undef;
}

sub isCUID {
    my $login = shift;

    return 0 unless defined $login;

    return $login =~ /^[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}$/;
}


sub add_user {
    my $this = shift;
    my ($charset, $authdomainid, $userinfo) = @_;
    my (@args, @fields, @query);

    $userinfo->{cuid} = $this->guid unless defined $userinfo->{cuid};
    $userinfo->{pid} = $authdomainid;
    while (my ($k, $v) = each %$userinfo) {
        push @args, $v;
        push @fields, $k;
        push @query, '?';
    }
    _uni($charset, @args);
    my @normalizers = split(/\s*,\s*/, $Foswiki::cfg{UnifiedAuth}{WikiNameNormalizers} || '');
    foreach my $n (@normalizers) {
        next if $n =~ /^\s*$/;
        $userinfo->{wiki_name} = $normalizers{$n}->($userinfo->{wiki_name}) if $userinfo->{wiki_name};
    }

    # make sure we have a valid topic name
    sub unidecode {
        my $text = shift;
            eval {
                require Text::Unidecode;
                $text = Text::Unidecode::unidecode($text);
            };
        return $text;
    }
    $userinfo->{wiki_name} =~ s/$Foswiki::cfg{NameFilter}/unidecode($_)/gi;
    $userinfo->{wiki_name} =~ s/$Foswiki::cfg{NameFilter}//gi;

    my $db = $this->db;
    my $has = sub {
        my $name = shift;
        return $db->selectrow_array("SELECT COUNT(wiki_name) FROM users WHERE wiki_name=?", {}, $name);
    };

    my $wn = $userinfo->{wiki_name};
    my $serial = 1;
    while ($has->($wn)) {
        $wn = $userinfo->{wiki_name} . $serial++;
    }
    $userinfo->{wiki_name} = $wn;

    my $fields = join(', ', @fields);
    my $q = join(', ', @query);
    $this->{db}->do("INSERT INTO users ($fields) VALUES($q)", {}, @args);
    $this->{db}->do("INSERT INTO merged_users (primary_cuid, mapped_cuid, primary_provider, mapped_provider) VALUES(?,?,?,?)", {},
        $userinfo->{cuid}, $userinfo->{cuid}, $authdomainid, $authdomainid);
    return $userinfo->{cuid};
}

sub delete_user {
    my ($this, $cuid) = @_;

    $this->{db}->do("DELETE FROM users WHERE cuid=?", {}, $cuid);
}

sub _uni {
    my $charset = shift;

    return unless $charset;

    for my $i (@_) {
        next if not defined $i || utf8::is_utf8($i);
        $i = decode($charset, $i);
    }
}

sub update_user {
    my ($this, $charset, $cuid, $userinfo) = @_;
    my (@args, @query);

    while (my ($k, $v) = each %$userinfo) {
        push @args, $v;
        push @query, "$k=?";
    }

    _uni($charset, @args);

    my $q = join(', ', @query);
    push @args, $cuid;
    return $this->db->do("UPDATE users SET $q WHERE cuid=?", {}, @args);
}

sub update_reset_request {
    my ($this, $charset, $cuid, $reset_id, $reset_limit) = @_;
    _uni($charset, $cuid, $reset_id, $reset_limit);
    return $this->db->do("UPDATE users SET reset_id=?, reset_limit=? WHERE cuid=?", {}, $reset_id, $reset_limit, $cuid);
}

sub update_wikiname {
    my ($this, $actions, $provider, $isDry) = @_;

    my $db = $this->db();

    my $pid = $db->selectrow_array("SELECT pid FROM providers WHERE name=?", {}, $provider);
    return { error => 'unknown provider' } unless defined $pid;

    $db->begin_work();

    my @report = ();
    my %clashes = ();
    my %resolved_clashes = ();
    my $errors = 0;
    my $updated = 0;
    my $successes = 0;
    foreach my $action (@$actions) {
        my $new_wiki_name = $action->{wiki_name};
        my %cuids = ();

        if($action->{login_name}) {
            foreach my $c ( @{$db->selectcol_arrayref("SELECT cuid FROM users WHERE login_name=? and pid=?", {}, $action->{login_name}, $pid)} ) {
                $cuids{$c} = 1;
            }
        }

        my @cuid_array = keys %cuids;
        if(scalar @cuid_array > 1) {
            push @report, { error => 'ambiguous', cuids => \@cuid_array, action => $action };
            $errors++;
            next;
        }
        if(scalar @cuid_array != 1) {
            push @report, { error => 'not found', action => $action };
            $errors++;
            next;
        }
        my $cuid = $cuid_array[0];

        my $result = {};

        # clashes
        my $inUse = $db->selectcol_arrayref("SELECT cuid FROM users WHERE wiki_name=?", {}, $new_wiki_name);
        if(scalar @$inUse == 1 && $inUse->[0] eq $cuid) {
            push @report, { success => 'no action', cuid => $cuid };
            $successes++;
            next;
        }

        foreach my $c (@$inUse) {
            my $count = 1;
            my $moved;
            do {
                $moved = $new_wiki_name . $count;
                $count++;
            } while ($db->selectrow_array("SELECT COUNT(cuid) FROM users WHERE wiki_name=?", {}, $moved));

            unless($isDry){
                $db->do("UPDATE users SET wiki_name=? where cuid=?", {}, $moved, $c);
            }
            $clashes{$c} = 1;
        }

        unless($isDry){
            $db->do("UPDATE users SET wiki_name=? where cuid=?", {}, $new_wiki_name, $cuid);
        }
        $updated++;
        if($clashes{$cuid}) {
            delete $clashes{$cuid};
            $resolved_clashes{$cuid} = 1;
        }

        push @report, { success => 'updated', cuid => $cuid };
        $successes++;
    }

    unless($isDry) {
        $db->commit();
    }

    return { success => 'done', report => \@report, clashes => [keys %clashes], resolved_clases => [keys %resolved_clashes], updated => $updated, errors => $errors, successes => $successes };
}

# Mockup for retrieval of users by search term.
# Does not yet support different fiels (login, email, ...).
sub queryUser {
    my ($this, $opts) = @_;
    my ($term, $maxrows, $page, $fields, $type, $basemapping) = (
        $opts->{term},
        $opts->{limit},
        $opts->{page},
        $opts->{searchable_fields},
        $opts->{type},
        $opts->{basemapping},
    );

    my $options = {Slice => {}};
    $maxrows = 10 unless defined $maxrows;
    $options->{MaxRows} = $maxrows if $maxrows;
    $page ||= 0;

    $term = '' unless defined $term;
    $term =~ s#^\s+##;
    $term =~ s#\s+$##;
    my @terms = split(/\s+/, $term);
    @terms = ('') unless @terms;
    @terms = map { "\%$_\%" } @terms;

    my $list;
    my $count;
    my $offset = $maxrows * $page;

    my $u_join = ''; # this will hold the join clause and 'ON' condition for
                     # users when the 'ingroup' option is active.
    my $ingroup = $this->getGroupAndParents(map {$_ =~ s#^\s+##r =~ s#\s+$##r} split(',', $opts->{ingroup})) if $opts->{ingroup};

    unless ($type eq 'group') {
        my @params;
        @{$fields} = map {
            push @params, @terms;
            $_ =~ s/([A-Z])/'_'.lc($1)/ger =~ s/[^a-z_]//gr
        } @{$fields};

        my @parts;
        map {
            my $f = $_;
            push @parts, join(' AND ', map {"$f ILIKE ?"} @terms)
        } @$fields;

        my $u_condition = join(' OR ', @parts);

        if($basemapping eq 'skip') {
            my $session = $Foswiki::Plugins::SESSION;
            $u_condition = "($u_condition) AND pid!='" . $this->authProvider($session, '__baseuser')->getPid() . "'";
        } elsif ($basemapping eq 'adminonly') {
            my $session = $Foswiki::Plugins::SESSION;
            my $base = $this->authProvider($session, '__baseuser');
            my $admin = $base->getAdminCuid();
            my $pid = $base->getPid();
            $u_condition = "($u_condition) AND (pid !='$pid' OR cuid='$admin')";
        }

        my $g_condition;
        if($type eq 'any') {
            $g_condition = join(' AND ', map { "name ILIKE ?" } @terms);
            push @params, @terms;
        }

        if($ingroup) {
            unless (scalar @$ingroup) {
                # group not found, make this a query that can not deliver any
                # results
                $u_join = " join group_members ON (pid=-1 AND pid=-2)";
                $g_condition = 'pid=-1 AND pid=-2' if $g_condition;
            } else {
                $u_join = " join group_members ON users.cuid=group_members.u_cuid AND (".join(' OR ', map{ "group_members.g_cuid=?" } @$ingroup).")";
                unshift @params, @$ingroup;
                if($g_condition) {
                    $g_condition .= " AND cuid IN (".(join(',', map{"?"} @$ingroup)).")";
                    push @params, @$ingroup;
                }
            }
        }


        my $statement;
        my $statement_count;
        if ($type eq 'any') {
            $statement = <<SQL;
SELECT
    'user' AS type,
    cuid AS cUID,
    login_name AS loginName,
    wiki_name as wikiName,
    display_name AS displayName,
    email
    FROM users $u_join
    WHERE deactivated=0 AND uac_disabled=0 AND ($u_condition)
UNION
SELECT
    'group' AS type,
    cuid AS cUID,
    name AS wikiName,
    name AS displayName,
    '' AS loginName,
    '' AS email
    FROM groups
    WHERE ($g_condition)
ORDER BY displayName
OFFSET $offset
SQL
            $statement_count = <<SQL;
SELECT
    COUNT(*)
    FROM (
SELECT
    cuid
    FROM users $u_join
    WHERE deactivated=0 AND uac_disabled=0 AND ($u_condition)
UNION
SELECT
    cuid
    FROM groups
    WHERE ($g_condition)
) AS gu
SQL
        } else {
            $statement = <<SQL;
SELECT
    'user' AS type,
    cuid AS cUID,
    login_name AS loginName,
    wiki_name as wikiName,
    display_name AS displayName
FROM users $u_join
WHERE deactivated=0 AND uac_disabled=0 AND ($u_condition)
ORDER BY displayName
OFFSET $offset
SQL
            $statement_count = <<SQL;
SELECT
    count(*)
FROM users $u_join
WHERE deactivated=0 AND uac_disabled=0 AND ($u_condition)
SQL
        }
        $list = $this->db->selectall_arrayref($statement, $options, @params);
        $count = $this->db->selectrow_array($statement_count, $options, @params);
    } else {
        my $condition = join(' AND ', map {"name ILIKE ?"} @terms);
        if($ingroup) {
            unless (scalar @$ingroup) {
                # group not found, make this a query that can not deliver any
                # results
                $condition = 'pid=-1 AND pid=-2';
            } else {
                $condition .= " AND cuid IN (".(join(',', map{"?"} @$ingroup)).")";
                push @terms, @$ingroup;
            }
        }
        $list = $this->db->selectall_arrayref(<<SQL, $options, @terms);
SELECT
    'group' AS type,
    cuid AS cUID,
    name AS wikiName
FROM groups
WHERE ($condition)
ORDER BY wikiName
OFFSET $offset
SQL
        $count = $this->db->selectrow_array(<<SQL, $options, @terms);
SELECT
    COUNT(*)
FROM groups
WHERE ($condition)
SQL
    }

    return ($list, $count);
}

sub _getNestedMemberships {
    my ($db, $g_cuids, $memberships, $seen) = @_;

    foreach my $grp ( @{$memberships} ) {
        next if $seen->{$grp};
        $seen->{$grp} = 1;
        push @$g_cuids, $grp;

        my $nested = $db->selectcol_arrayref(<<SQL, {}, $grp);
SELECT nested_groups.child FROM nested_groups WHERE nested_groups.parent=?
SQL

        _getNestedMemberships($db, $g_cuids, $nested, $seen) if $nested;
    }
}

# Retrieve a group (or multiple) and all nested groups.
#
# Parameters:
#    * $this
#    * anything more will be treated as a group
#
# Returns:
#    * Arrayref of groups, containing the passed in groups and their nested
#      groups
sub getGroupAndParents {
    my $this = shift;

    my @cuids = grep{$_} map{$this->getCUID($_, 1)} @_;
    my @g_cuids = ();
    my $db = $this->db();

    # Maybe we should realize this as a stored procedure?
    _getNestedMemberships($db, \@g_cuids, \@cuids, {}) if scalar @cuids;

    return \@g_cuids;
}

sub handleScript {
    my $session = shift;

    my $req = $session->{request};
    # TODO
}

sub getProviderForUser {
    my ($this, $user) = @_;

    my $db = $this->db();
    return $db->selectrow_array("SELECT name, pid FROM users NATURAL JOIN providers WHERE cuid=?", {}, $user) if isCUID($user);
    my @row = $db->selectrow_array("SELECT name, pid FROM users NATURAL JOIN providers WHERE (login_name=? OR wiki_name=?)", {}, $user, $user);

    return @row;
}

sub authProvider {
    my ($this, $session, $id) = @_;

    return $this->{providers}->{$id} if $this->{providers}->{$id};

    my $cfg = $Foswiki::cfg{UnifiedAuth}{Providers}{$id};
    unless ($cfg) {
        $cfg = $internal_cfg->{$id};
        die "Provider not configured: $id" unless $cfg;
    }

    if ($cfg->{module} =~ /^Foswiki::Users::/) {
        die("Auth providers based on Foswiki password managers are not supported yet");
        #return Foswiki::UnifiedAuth::Providers::Passthrough->new($this->{session}, $id, $cfg);
    }

    my $package = "Foswiki::UnifiedAuth::Providers::$cfg->{module}";
    eval "require $package"; ## no critic (ProhibitStringyEval);
    if ($@ ne '') {
        use Carp qw(confess); confess("Failed loading auth: $id with $@");
        die "Failed loading auth provider: $@";
    }
    my $authProvider = $package->new($session, $id, $cfg->{config});

    $this->{providers}->{$id} = $authProvider;
    return $authProvider;
}

sub getPid {
    my ($this, $id) = @_;

    my $db = $this->db;
    my $pid = $db->selectrow_array("SELECT pid FROM providers WHERE name=?", {}, $id);

    return $pid if($pid);

    Foswiki::Func::writeWarning("Could not get pid of $id; creating a new one...");
    $db->do("INSERT INTO providers (name) VALUES(?)", {}, $id);
    return $this->getPid($id);
}

sub getOrCreateGroup {
    my ($this, $grpName, $pid) = @_;

    my $db = $this->{db};

    my $cuid = $db->selectrow_array(
        'SELECT cuid FROM groups WHERE name=? and pid=?', {}, $grpName, $pid);
    return $cuid if $cuid;

    $cuid = Data::GUID->guid;

    $db->begin_work;
    $db->do(
        'INSERT INTO groups (cuid, name, pid) VALUES(?, ?, ?)',
        {}, $cuid, $grpName, $pid);
    $db->commit;

    return $cuid;
}

sub removeGroup {
    my ($this, %group) = @_;

    # TODO: retain cuids and nestings in case the group re-appears (eg. malfunctioning ldap)

    my $db = $this->{db};

    my $cuid;
    if($group{cuid}) {
        $cuid = $group{cuid};
    } else {
        my $name = $group{name};
        my $pid = $group{pid};

        die unless $name && defined $pid; # XXX
        $cuid = $db->selectrow_array('SELECT cuid FROM groups WHERE name=? AND pid=?',
            {}, $name, $pid);
    }
    die unless $cuid; # XXX

    $db->begin_work;
    $db->do(
        'DELETE FROM groups WHERE cuid=?',
        {}, $cuid);
    $db->do(
        'DELETE FROM group_members WHERE g_cuid=?',
        {}, $cuid);
    $db->do(
        'DELETE FROM nested_groups WHERE parent=? OR child=?',
        {}, $cuid, $cuid);
    $db->commit;
}

sub updateGroup {
    my ($this, $pid, $group, $members, $nested) = @_;

    my $db = $this->{db};

    my $cuid = $this->getOrCreateGroup($group, $pid);

    my $currentMembers = {};
    my $currentGroups = {};

    # get current users
    { # scope
        my $fromDb = $db->selectcol_arrayref('SELECT u_cuid FROM group_members WHERE g_cuid=?', {}, $cuid);
        foreach my $item ( @$fromDb ) {
            $currentMembers->{$item} = 0;
        }
    }
    # get current nested groups
    { # scope
        my $fromDb = $db->selectcol_arrayref('SELECT child FROM nested_groups WHERE parent=?', {}, $cuid);
        foreach my $item ( @$fromDb ) {
            $currentGroups->{$item} = 0;
        }
    }

    $db->begin_work;
    # add users / groups
    foreach my $item ( @$members ) {
        unless(defined $currentMembers->{$item}) {
            $db->do('INSERT INTO group_members (g_cuid, u_cuid) VALUES(?,?)', {}, $cuid, $item);
        }
        $currentMembers->{$item} = 1;
    }
    foreach my $item ( @$nested ) {
        unless(defined $currentGroups->{$item}) {
            $db->do('INSERT INTO nested_groups (parent, child) VALUES(?,?)', {}, $cuid, $item);
        }
        $currentGroups->{$item} = 1;
    }

    # remove users/groups no longer present
    foreach my $item ( keys %$currentMembers ) {
        unless ($currentMembers->{$item}) {
            $db->do('DELETE FROM group_members WHERE g_cuid=? AND u_cuid=?', {}, $cuid, $item);
        }
    }
    foreach my $item ( keys %$currentGroups ) {
        unless ($currentGroups->{$item}) {
            $db->do('DELETE FROM nested_groups WHERE parent=? AND child=?', {}, $cuid, $item);
        }
    }
    $db->commit();
}

sub checkPassword {
    my ( $this, $session, $login, $password ) = @_;

    my $db = $this->db();
    my $providers = $db->selectcol_arrayref(
        'SELECT p.name FROM users as u, providers as p WHERE u.pid = p.pid AND login_name=? ORDER BY p.name', {}, $login) || [];
    foreach my $provider_id (@$providers) {
        my $provider = $this->authProvider($session, $provider_id);
        next unless $provider->can('checkPassword');
        return 1 if $provider->checkPassword($login, $password);
    }

    return undef;
}

sub setPassword {
    my ( $this, $session, $login, $newUserPassword, $oldUserPassword ) = @_;

    my $passwordChanged;
    my $db = $this->db();
    my $providers = $db->selectcol_arrayref(
        'SELECT p.name FROM users as u, providers as p WHERE u.pid = p.pid AND login_name=? ORDER BY p.name', {}, $login) || [];
    foreach my $provider_id (@$providers) {
        my $provider = $this->authProvider($session, $provider_id);
        next unless $provider->can('setPassword');
        $passwordChanged = 1 if $provider->setPassword($login, $newUserPassword, $oldUserPassword);
    }

    return $passwordChanged;
}

1;
