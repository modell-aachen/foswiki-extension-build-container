package Foswiki::UnifiedAuth::Providers::Ldap;

use Error;
use JSON;
use Net::CIDR;

use Net::LDAP qw(LDAP_REFERRAL);
use URI::ldap;
use Net::LDAP::Constant qw(LDAP_SUCCESS LDAP_SIZELIMIT_EXCEEDED LDAP_CONTROL_PAGED);
use Net::LDAP::Extension::SetPassword;

use strict;
use warnings;

use Foswiki::Plugins::UnifiedAuthPlugin;
use Foswiki::UnifiedAuth;
use Foswiki::UnifiedAuth::IdentityProvider;
our @ISA = qw(Foswiki::UnifiedAuth::IdentityProvider);

my @schema_updates = (
    [
        "CREATE TABLE IF NOT EXISTS users_ldap (
            pid INTEGER NOT NULL,
            info JSONB NOT NULL,
            login TEXT NOT NULL,
            cuid UUID NOT NULL,
            dn TEXT NOT NULL,
            PRIMARY KEY (login,pid)
        )",
    ]
);
my $schema_xxx = "INSERT INTO meta (type, version) VALUES('users_ldap', 1)"; # XXX must fake upsert

sub new {
    my ($class, $session, $id, $config) = @_;

    my $this = $class->SUPER::new($session, $id, $config);

    return $this;
}

sub makeConfig {
    my $this = shift;

    $this->{ldap} = undef;    # connect later
    $this->{error} = undef;
    $this->{host} = $this->{config}{Host} || 'localhost';
    $this->{base} = $this->{config}{Base} || '';
    $this->{port} = $this->{config}{Port} || 389;
    $this->{version} = $this->{config}{Version} || 3;
    $this->{ipv6} = $this->{config}{IPv6} || 0;

    $this->{userBase} = $this->{config}{UserBase}
        || [$this->{config}{Base}]
        || [];

    $this->{userScope} = $this->{config}{UserScope}
        || 'sub';

    $this->{groupBase} = $this->{config}{GroupBase}
        || $this->{config}{Base}
        || [];

    $this->{groupScope} = $this->{config}{GroupScope}
        || 'sub';

    $this->{loginAttribute} = $this->{config}{LoginAttribute} || 'sAMAccountName';
    $this->{allowChangePassword} = $this->{config}{AllowChangePassword} || 0;

    $this->{wikiNameAttribute} = $this->{config}{WikiNameAttributes}
        || $this->{config}{WikiNameAttribute}
        || 'givenName,sn';

    $this->{wikiNameAliases} = $this->{config}{WikiNameAliases} || '';

    $this->{userMappingTopic} = $this->{config}{UserMappingTopic} || '';

    $this->{normalizeWikiName} = $this->{config}{NormalizeWikiNames} || 1;
    $this->{normalizeLoginName} = $this->{config}{NormalizeLoginNames} || 0;
    $this->{caseSensitiveLogin} = $this->{config}{CaseSensitiveLogin} || 0;
    $this->{normalizeGroupName} = $this->{config}{NormalizeGroupNames} || 0;
    $this->{ignorePrivateGroups} = $this->{config}{IgnorePrivateGroups} || 1;

    $this->{loginFilter} = $this->{config}{LoginFilter} || 'objectClass=person';

    $this->{groupAttribute} = $this->{config}{GroupAttribute} || 'cn';
    $this->{primaryGroupAttribute} = $this->{config}{PrimaryGroupAttribute} || 'gidNumber';
    $this->{groupFilter} = $this->{config}{GroupFilter} || 'objectClass=group';
    $this->{memberAttribute} = $this->{config}{MemberAttribute} || 'member';
    $this->{innerGroupAttribute} = $this->{config}{InnerGroupAttribute} || 'member';
    $this->{memberIndirection} = $this->{config}{MemberIndirection} || 1;
    $this->{nativeGroupsBackoff} = $this->{config}{WikiGroupsBackoff} || 1;
    $this->{bindDN} = $this->{config}{BindDN} || '';
    $this->{bindPassword} = $this->{config}{BindPassword} || '';
    $this->{mapGroups} = $this->{config}{MapGroups} || 0;
    $this->{rewriteGroups} = $this->{config}{RewriteGroups} || {};
    $this->{rewriteWikiNames} = $this->{config}{RewriteWikiNames} ||  { '^(.*)@.*$' => '$1' };
    $this->{rewriteLoginNames} = $this->{config}{RewriteLoginNames} || [];
    $this->{mergeGroups} = $this->{config}{MergeGroups} || 0;

    $this->{mailAttribute} = $this->{config}{MailAttribute} || 'mail';
    $this->{displayAttributes} = $this->{config}{DisplayAttributes} || 'displayName';

    $this->{exclude} = $this->{config}{Exclude}
        || 'WikiGuest, ProjectContributor, RegistrationAgent, AdminGroup, NobodyGroup';

    $this->{pageSize} = $this->{config}{PageSize};
    $this->{isConnected} = 0;
    $this->{maxCacheAge} = $this->{config}{MaxCacheAge};

    $this->{useSASL} = $this->{config}{UseSASL} || 0;
    $this->{saslMechanism} = $this->{config}{SASLMechanism} || 'PLAIN CRAM-MD4 EXTERNAL ANONYMOUS';
    $this->{krb5CredCache} = $this->{config}{Krb5CredentialsCacheFile};

    $this->{useTLS} = $this->{config}{UseTLS} || 0;
    $this->{tlsVerify} = $this->{config}{TLSVerify} || 'require';
    $this->{tlsSSLVersion} = $this->{config}{TLSSSLVersion} || 'tlsv1';
    $this->{tlsCAFile} = $this->{config}{TLSCAFile} || '';
    $this->{tlsCAPath} = $this->{config}{TLSCAPath} || '';
    $this->{tlsClientCert} = $this->{config}{TLSClientCert} || '';
    $this->{tlsClientKey} = $this->{config}{TLSClientKey} || '';


    $this->{pageSize} = 200 unless defined $this->{pageSize};

    unless (ref($this->{userBase})) {
        $this->{userBase} = [$this->{userBase}];
    }

    unless (ref($this->{groupBase})) {
        $this->{groupBase} = [$this->{groupBase}];
    }

    if ($this->{useSASL}) {
        #writeDebug("will use SASL authentication");
        require Authen::SASL;
    }

    # normalize normalization flags
    $this->{normalizeWikiName} = $this->{config}{NormalizeWikiName}
        unless defined $this->{normalizeWikiName};
    $this->{normalizeWikiName} = 1
        unless defined $this->{normalizeWikiName};
    $this->{normalizeLoginName} = $this->{config}{NormalizeLoginName}
        unless defined $this->{normalizeLoginName};
    $this->{normalizeGroupName} = $Foswiki::cfg{Ldap}{NormalizeGroupName}
        unless defined $this->{normalizeGroupName};

    @{$this->{wikiNameAttributes}} = split(/\s*,\s*/, $this->{wikiNameAttribute});
    $this->{displayAttributes} = [ split(/\s*,\s*/, $this->{displayAttributes}) ];

    # create exclude map
    my %excludeMap;
    if ($this->{caseSensitiveLogin}) {
        %excludeMap = map { $_ => 1 } split(/\s*,\s*/, $this->{exclude});
    } else {
        %excludeMap = map { $_ => 1, lc($_) => 1 } split(/\s*,\s*/, $this->{exclude});
    }
    $this->{excludeMap} = \%excludeMap;

    # creating alias map
    my %aliasMap = ();
    foreach my $alias (split(/\s*,\s*/, $this->{wikiNameAliases})) {
        if ($alias =~ /^\s*(.+?)\s*=\s*(.+?)\s*$/) {
            $aliasMap{$1} = $2;
        }
    }
    $this->{wikiNameAliases} = \%aliasMap;

    # default value for cache expiration is every 24h
    $this->{maxCacheAge} = 86400 unless defined $this->{maxCacheAge};

    #writeDebug("constructed a new LdapContrib object");

    $this->{uauth} = Foswiki::UnifiedAuth->new();
    $this->{displayNameFormat} = $this->{config}{DisplayNameFormat} || '$cn';
    my @xxx = @schema_updates;
    unless($this->{uauth}->db->selectrow_array("SELECT COUNT(version) FROM meta WHERE type='users_ldap'")) {
        push @xxx, $schema_xxx;
    }
    $this->{uauth}->apply_schema('users_ldap', @schema_updates);

    return $this;
}

sub fromLdapCharSet {
    my ($this, $string) = @_;

    return undef unless defined $string;

    my $ldapCharSet = $this->{config}{CharSet} || 'utf-8';

    if ($Foswiki::UNICODE) {
        return Encode::decode($ldapCharSet, $string);
    }
    my $siteCharSet = $Foswiki::cfg{Site}{CharSet};

    Encode::from_to($string, $ldapCharSet, $siteCharSet) unless $ldapCharSet eq $siteCharSet;
    return $string;
}

sub connect {
    my ($this, $dn, $passwd, $host, $port) = @_;

    $host ||= $this->{host};
    $port ||= $this->{port};

    $this->{ldap} = Net::LDAP->new(
        $host,
        port => $port,
        version => $this->{version},
        inet4 => ($this->{ipv6}?0:1),
        inet6 => ($this->{ipv6}?1:0),
        timeout => 5, # TODO: make configurable
    );

    unless ($this->{ldap}) {
        $this->{error} = "failed to connect to $this->{host}";
        $this->{error} .= ": $@" if $@;
        $this->{isConnected} = 0;
        return 0;
    }

    # TLS bind
    if ($this->{useTLS}) {
        my %args = (
            verify => $this->{tlsVerify},
            cafile => $this->{tlsCAFile},
            capath => $this->{tlsCAPath},
        );
        $args{"clientcert"} = $this->{tlsClientCert} if $this->{tlsClientCert};
        $args{"clientkey"} = $this->{tlsClientKey} if $this->{tlsClientKey};
        $args{"sslversion"} = $this->{tlsSSLVersion} if $this->{tlsSSLVersion};
        my $msg = $this->{ldap}->start_tls(%args);
        writeDebug($msg->{errorMessage}) if $msg->{errorMessage};
    }

    $dn = $this->toLdapCharSet($dn) if $dn;
    $passwd = $this->toLdapCharSet($passwd) if $passwd;

    # authenticated bind
    my $msg;
    if (defined($dn)) {
        die "illegal call to connect()" unless defined($passwd);
        $msg = $this->{ldap}->bind($dn, password => $passwd);
    } else {
        # proxy user
        if ($this->{useSASL}) {
            # sasl bind
            my $sasl = Authen::SASL->new(
                mechanism => $this->{saslMechanism},    #'DIGEST-MD5 PLAIN CRAM-MD5 EXTERNAL ANONYMOUS',
            );
            $sasl = $sasl->client_new('ldap', $host);

            my $krb5keytab = $ENV{KRB5CCNAME};
            if (my $newkeytab = $this->{krb5CredCache}) {
                $krb5keytab = "FILE:$newkeytab";
            }
            local $ENV{KRB5CCNAME};
            $ENV{KRB5CCNAME} = $krb5keytab if $this->{krb5CredCache};

            if ($this->{bindDN} && $this->{bindPassword}) {
                my $bindDN = $this->toLdapCharSet($this->{bindDN});
                $sasl->callback(
                    user => $bindDN,
                    pass => $this->{bindPassword},
                );
                $msg = $this->{ldap}->bind($bindDN, sasl => $sasl, version => $this->{version});

            } else {
                $msg = $this->{ldap}->bind(sasl => $sasl, version => $this->{version});
            }

        } elsif ($this->{bindDN} && $this->{bindPassword}) {
            # simple bind
            $msg = $this->{ldap}->bind($this->toLdapCharSet($this->{bindDN}),
                password => $this->toLdapCharSet($this->{bindPassword}));
        } else {
            # anonymous bind
            $msg = $this->{ldap}->bind;
        }

    }

    $this->{isConnected} = ($this->checkError($msg) == LDAP_SUCCESS) ? 1 : 0;
    return $this->{isConnected};
}

sub toLdapCharSet {
    my ($this, $string) = @_;

    my $ldapCharSet = $Foswiki::cfg{Ldap}{CharSet} || 'utf-8';

    if ($Foswiki::UNICODE) {
        return Encode::encode($ldapCharSet, $string);
    }
    my $siteCharSet = $Foswiki::cfg{Site}{CharSet};

    Encode::from_to($string, $siteCharSet, $ldapCharSet) unless $ldapCharSet eq $siteCharSet;
    return $string;
}

sub disconnect {
    my $ldap = shift;

    return unless defined($ldap->{ldap}) && $ldap->{isConnected};

    #writeDebug("called disconnect()");
    $ldap->{ldap}->unbind();
    $ldap->{ldap} = undef;
    $ldap->{isConnected} = 0;
}


sub supportsRegistration {
    0;
}

sub useDefaultLogin {
    1;
}

# Will refresh ALL groups and users, unless a cuid is provided.
# When a cuid is passed in, only delegate to super class; DO NOT refresh cache
# for that cuid!
sub refresh {
    my ( $this, $cuid ) = @_;

    return $this->SUPER::refresh($cuid) if $cuid;

    my $pid = $this->getPid();
    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;

    $this->makeConfig();

    $this->refreshCache(1);
    return $this->SUPER::refresh();
}

sub writeDebug {
    Foswiki::Func::writeWarning(@_);
}

sub getData {
    my ($this, %args) = @_;

    # use the control LDAP extension only if a valid pageSize value has been provided
    my $page;
    my $cookie;
    if ($this->{pageSize} > 0) {
        require Net::LDAP::Control::Paged;
        $page = Net::LDAP::Control::Paged->new(size => $this->{pageSize});
        $args{control} = [$page];
        writeDebug("reading users from cache with page size=$this->{pageSize}");
    } else {
        writeDebug("reading users from cache in one chunk");
    }

    # read pages
    my $gotError = 0;

    my $fromLdap = [];

    $args{callback} = sub {
        my ($ldap, $entry) = @_;
        push @$fromLdap, $entry;
    };

    while (1) {

        # perform search
        my $mesg = $this->search(%args);
        unless ($mesg) {
            writeDebug("error refreshing the cache: " . $this->getError());
            my $code = $this->getCode();
            $gotError = 1 if !defined($code) || $code != LDAP_SIZELIMIT_EXCEEDED;    # continue on sizelimit exceeded
            last;
        }

        # only use cookies and pages if we are using this extension
        if ($page) {
            # get cookie from paged control to remember the offset
            my ($resp) = $mesg->control(LDAP_CONTROL_PAGED) or last;

            $cookie = $resp->cookie or last;
            if ($cookie) {
                # set cookie in paged control
                $page->cookie($cookie);
            } else {
                # found all
                #writeDebug("ok, no more cookie");
                last;
            }
        } else {
            # one chunk ends here
            last;
        }
    }    # end reading pages

    #writeDebug("done reading pages");

    # clean up
    if ($cookie) {
        $page->cookie($cookie);
        $page->size(0);
        $this->search(%args);
    }
    return ($fromLdap, $gotError);
}

sub refreshUsersCache {
    my ($this, $data, $userBase) = @_;

    writeDebug("called refreshUsersCache($userBase)");
    $data ||= $this->{data};
    $userBase ||= $this->{base};

    # prepare search
    my %args = (
        filter => $this->{loginFilter},
        base => $userBase,
        scope => $this->{userScope},
        deref => "always",
        attrs => [$this->{loginAttribute}, $this->{mailAttribute}, $this->{primaryGroupAttribute}, @{$this->{wikiNameAttributes}}, @{$this->{displayAttributes}}, 'userAccountControl'],
    );

    my ($fromLdap, $gotError, $nrRecords) = $this->getData(%args);

    # check for error
    return 0 if $gotError;

    foreach my $entry ( @$fromLdap ) {
        $this->cacheUserFromEntry($entry);
    }

    return 1;
}

sub refreshGroupsCache {
    my ($this, $data, $groupBase) = @_;

    writeDebug("called refreshGroupsCache($groupBase)");
    $data ||= $this->{data};
    $groupBase ||= $this->{base};

    my $pid = $this->getPid();

    # prepare search
    my %args = (
        filter => $this->{groupFilter},
        base => $groupBase,
        scope => $this->{groupScope},
        deref => "always",
        attrs => [$this->{groupAttribute}, $this->{memberAttribute}, $this->{innerGroupAttribute}, $this->{primaryGroupAttribute}],
    );

    my ($fromLdap, $gotError, $nrRecords) = $this->getData(%args);

    # check for error
    return 0 if $gotError;

    my $groupsCache = {}; # maps name -> ldap entry
    my $groupsCacheDN = {}; # maps dn -> name
    foreach my $entry ( @$fromLdap ) {
        $this->cacheGroupFromEntry($entry, $groupsCache, $groupsCacheDN);
    }

    my $db = $this->{uauth}->db();
    # Note: Selecting users from ALL ldaps (not filtered by pid), because one
    # might want to configure multiple ldaps for multiple branches, but still
    # have groups containing users from all branches. The DNs should be enough
    # to distinguish members coming from different ldaps entirely.
    my $users = $db->selectall_hashref('SELECT dn, cuid FROM users_ldap', 'dn', {});
    my $oldGroups = $db->selectcol_arrayref('SELECT name FROM groups WHERE pid=?', {}, $pid);

    $this->_processGroups($groupsCache, $groupsCacheDN, $users);
    $this->_processVirtualGroups($groupsCache, $users);

    # kick removed groups
    foreach my $oldName ( @$oldGroups ) {
        unless ($groupsCache->{$oldName}) {
            $this->{uauth}->removeGroup(name => $oldName, pid => $pid);
        }
    }

    return 1;
}

sub cacheGroupFromEntry {
    my ($this, $entry, $groups, $groupsDN) = @_;

    my $dn = $this->fromLdapCharSet($entry->dn());
    writeDebug("caching group for $dn");

    my $groupName = $entry->get_value($this->{groupAttribute});
    unless ($groupName) {
        writeDebug("no groupName for $dn ... skipping");
        return 0;
    }
    $groupName =~ s/^\s+//o;
    $groupName =~ s/\s+$//o;
    $groupName = $this->fromLdapCharSet($groupName);

    if ($this->{normalizeGroupName}) {
        $groupName = $this->normalizeWikiName($groupName);
    }
    return 0 if $this->{excludeMap}{$groupName};

    # check for a rewrite rule
    my $foundRewriteRule = 0;
    my $oldGroupName = $groupName;
    foreach my $pattern (keys %{$this->{rewriteGroups}}) {
        my $subst = $this->{rewriteGroups}{$pattern};
        if ($groupName =~ /^(?:$pattern)$/) {
            my $arg1 = $1;
            my $arg2 = $2;
            my $arg3 = $3;
            my $arg4 = $4;
            my $arg5 = $5;
            $arg1 = '' unless defined $arg1;
            $arg2 = '' unless defined $arg2;
            $arg3 = '' unless defined $arg3;
            $arg4 = '' unless defined $arg4;
            $subst =~ s/\$1/$arg1/g;
            $subst =~ s/\$2/$arg2/g;
            $subst =~ s/\$3/$arg3/g;
            $subst =~ s/\$4/$arg4/g;
            $subst =~ s/\$5/$arg5/g;
            $groupName = $subst;
            $foundRewriteRule = 1;
            writeDebug("rewriting '$oldGroupName' to '$groupName' using rule $pattern");
            last;
        }
    }

    # TODO
    if (!$this->{mergeGroups} && defined($groups->{$groupName})) {
        # TODO: will only print a stupid hashref
        writeDebug("$dn clashes with group $groups->{$groupName} on $groupName");
        return 0;
    }

    my $loginName = $this->{caseSensitiveLogin} ? $groupName : lc($groupName);
    $loginName =~ s/([^a-zA-Z0-9])/'_'.sprintf('%02x', ord($1))/ge;


    $groups->{$loginName} = $entry;
    $groupsDN->{$dn} = $loginName;

    # TODO
    # resolve primary group memberships.
    # ...

    # TODO: add range syntax

    return 1;
}

sub _processGroups {
    my ($this, $groups, $groupsDN, $users) = @_;

    my $uauth = $this->{uauth};
    my $db = $uauth->db();

    foreach my $groupName ( keys %$groups ) {
        my $entry = $groups->{$groupName};

        # fetch all members of this group
        my $memberVals = $entry->get_value($this->{memberAttribute}, alloptions => 1);
        my @members = (defined($memberVals) && exists($memberVals->{''})) ? @{$memberVals->{''}} : ();
        my $nested = [];
        if (! scalar(@members)) {
            while(1) {
                my ($rangeEnd, $range_members);
                foreach my $k (keys %$memberVals) {
                    next if $k !~ /^;range=(?:\d+)-(\*|\d+)$/o;
                    ($rangeEnd, $range_members) = ($1, $memberVals->{$k});
                    last;
              }

              last if !defined $rangeEnd;
              push @members, @$range_members;
              last if $rangeEnd eq '*';
              $rangeEnd++;

              # Apparently there are more members, so iterate
              # Apparently we need a dummy filter to make this work#
              my $dn = $this->fromLdapCharSet($entry->dn());
              my $newRes = $this->search(filter => 'objectClass=*', base => $dn, scope => 'base', attrs => ["member;range=$rangeEnd-*"]);
              unless ($newRes) {
                writeDebug("error fetching more members for $dn: " . $this->getError());
                last;
              }

              my $newEntry = $newRes->pop_entry();
              if (!defined $newEntry) {
                writeDebug("no result when doing member;range=$rangeEnd-* search for $dn\n");
                last;
              }

              $memberVals = $newEntry->get_value($this->{memberAttribute}, alloptions => 1);
            }
        }

        my $ua_members = [];
        foreach my $member ( @members ) {
            $member = $this->fromLdapCharSet($member);
            if ($groupsDN->{$member}) {
                $member = $groupsDN->{$member};
            }
            if ($groups->{$member}) {
                push @$nested, $uauth->getOrCreateGroup($member, $this->getPid());
            } elsif ($users->{$member}) {
                push @$ua_members, $users->{$member}->{cuid};
            }
        }

        $uauth->updateGroup($this->getPid(), $groupName, $ua_members, $nested);
    }
}

sub _processVirtualGroups {
    my ($this, $groupsCache, $users) = @_;
    # prepare search
    foreach my $virtualGroup (@{$this->{config}->{VirtualGroups}}){
        my $groupName = $virtualGroup->{name};
        if($groupsCache->{$groupName}){
            writeDebug("Error while creating virtual group '$groupName'. A group with the same name already exists. Skipping.");
            next;
        }
        my %args = (
            filter => $virtualGroup->{memberQuery},
            deref => "always",
            attrs => []
        );

        my ($fromLdap, $gotError, $nrRecords) = $this->getData(%args);
        if($gotError){
            writeDebug("Error while querying members for virtual group '$groupName'. Skipping.");
            next;
        }
        my @members;
        foreach my $entry ( @$fromLdap ) {
            my $userDn = $entry->dn();
            if($users->{$userDn}){
                push @members, $users->{$userDn}->{cuid};
            }
        }
        $this->{uauth}->updateGroup($this->getPid(), $groupName, \@members);
        $groupsCache->{$groupName} = 1;
    }
}

sub search {
    my ($this, %args) = @_;

    $args{base} = $this->{base} unless $args{base};
    $args{scope} = 'sub' unless $args{scope};
    $args{sizelimit} = 0 unless $args{sizelimit};
    $args{attrs} = ['*'] unless $args{attrs};

    if (defined($args{callback}) && !defined($args{_origCallback})) {

        $args{_origCallback} = $args{callback};

        $args{callback} = sub {
            my ($ldap, $entry) = @_;

            # bail out when done
            return unless defined $entry;

            # follow references
            if ($entry->isa("Net::LDAP::Reference")) {
                foreach my $link ($entry->references) {
                    #TODO: This method is not implemented!
                    #writeDebug("following reference $link");
                    #$this->_followLink($link, %args);
                }
            } else {
                # call the orig callback
                $args{_origCallback}($ldap, $entry);
            }
        };
    }

    if ($Foswiki::cfg{Ldap}{Debug}) {
        my $attrString = join(',', @{$args{attrs}});
        writeDebug("called search(filter=$args{filter}, base=$args{base}, scope=$args{scope}, sizelimit=$args{sizelimit}, attrs=$attrString)");
    }

    unless ($this->{ldap}) {
        unless ($this->connect()) {
            writeDebug("error in search: " . $this->getError());
            return undef;
        }
    }

    # Re-encode all the parameters
    for my $k (keys %args) {
        next if ref $args{$k};
        $args{$k} = $this->toLdapCharSet($args{$k});
    }

    my $msg = $this->{ldap}->search(%args);
    my $errorCode = $this->checkError($msg);

    # we set a sizelimit so it is ok that it exceeds
    if ($args{sizelimit} && $errorCode == LDAP_SIZELIMIT_EXCEEDED) {
        writeDebug("sizelimit exceeded");
        return $msg;
    }

    if ($errorCode == LDAP_REFERRAL) {
        unless ($this->{_followingLink}) {
            my @referrals = $msg->referrals;
            foreach my $link (@referrals) {
                writeDebug("following referral $link");
                $this->_followLink($link, %args);
            }
        }
    } elsif ($errorCode != LDAP_SUCCESS) {
        writeDebug("error in search: " . $this->getError());
        return undef;
    }

    return $msg;
}

sub checkError {
    my ($this, $msg) = @_;

    my $code = $this->{code} = $msg->code();
    if ($code == LDAP_SUCCESS || $code == LDAP_REFERRAL) {
        $this->{error} = undef;
    } else {
        $this->{error} = $code . ': ' . $msg->error();
        #writeDebug($this->{error});
    }

    return $code;
}

sub getCode {
    return $_[0]->{code};
}

sub getError {
    return $_[0]->{error};
}

sub rewriteLoginName {
    my ($this, $name) = @_;

    foreach my $rule (@{$this->{rewriteLoginNames}}) {
        my $pattern = $rule->[0];
        my $subst = $rule->[1];
        if ($name =~ /^(?:$pattern)$/) {
            my $arg1 = $1;
            my $arg2 = $2;
            my $arg3 = $3;
            my $arg4 = $4;
            my $arg5 = $5;
            $arg1 = '' unless defined $arg1;
            $arg2 = '' unless defined $arg2;
            $arg3 = '' unless defined $arg3;
            $arg4 = '' unless defined $arg4;
            $subst =~ s/\$1/$arg1/g;
            $subst =~ s/\$2/$arg2/g;
            $subst =~ s/\$3/$arg3/g;
            $subst =~ s/\$4/$arg4/g;
            $subst =~ s/\$5/$arg5/g;
            writeDebug("rewriting '$name' to '$subst' using rule $pattern");
            return $subst;
        }
    }
    return $name;
}

sub transliterate {
    my $string = shift;

    if ($Foswiki::UNICODE || $Foswiki::cfg{Site}{CharSet} =~ /^utf-?8$/i) {
        use bytes;
        $string =~ s/\xc3\xa0/a/go;    # a grave
        $string =~ s/\xc3\xa1/a/go;    # a acute
        $string =~ s/\xc3\xa2/a/go;    # a circumflex
        $string =~ s/\xc3\xa3/a/go;    # a tilde
        $string =~ s/\xc3\xa4/ae/go;   # a uml
        $string =~ s/\xc3\xa5/a/go;    # a ring above
        $string =~ s/\xc3\xa6/ae/go;   # ae
        $string =~ s/\xc4\x85/a/go;    # a ogonek

        $string =~ s/\xc3\x80/A/go;    # A grave
        $string =~ s/\xc3\x81/A/go;    # A acute
        $string =~ s/\xc3\x82/A/go;    # A circumflex
        $string =~ s/\xc3\x83/A/go;    # A tilde
        $string =~ s/\xc3\x84/Ae/go;   # A uml
        $string =~ s/\xc3\x85/A/go;    # A ring above
        $string =~ s/\xc3\x86/AE/go;   # AE
        $string =~ s/\xc4\x84/A/go;    # A ogonek

        $string =~ s/\xc3\xa7/c/go;    # c cedille
        $string =~ s/\xc4\x87/c/go;    # c acute
        $string =~ s/\xc4\x8d/c/go;    # c caron
        $string =~ s/\xc3\x87/C/go;    # C cedille
        $string =~ s/\xc4\x86/C/go;    # C acute
        $string =~ s/\xc4\x8c/C/go;    # C caron

        $string =~ s/\xc4\x8f/d/go;    # d caron
        $string =~ s/\xc4\x8e/D/go;    # D caron

        $string =~ s/\xc3\xa8/e/go;    # e grave
        $string =~ s/\xc3\xa9/e/go;    # e acute
        $string =~ s/\xc3\xaa/e/go;    # e circumflex
        $string =~ s/\xc3\xab/e/go;    # e uml
        $string =~ s/\xc4\x9b/e/go;    # e caron

        $string =~ s/\xc4\x99/e/go;    # e ogonek
        $string =~ s/\xc4\x98/E/go;    # E ogonek
        $string =~ s/\xc4\x9a/E/go;    # E caron

        $string =~ s/\xc3\xb2/o/go;    # o grave
        $string =~ s/\xc3\xb3/o/go;    # o acute
        $string =~ s/\xc3\xb4/o/go;    # o circumflex
        $string =~ s/\xc3\xb5/o/go;    # o tilde
        $string =~ s/\xc3\xb6/oe/go;   # o uml
        $string =~ s/\xc3\xb8/o/go;    # o stroke

        $string =~ s/\xc3\xb3/o/go;    # o acute
        $string =~ s/\xc3\x93/O/go;    # O acute

        $string =~ s/\xc3\x92/O/go;    # O grave
        $string =~ s/\xc3\x93/O/go;    # O acute
        $string =~ s/\xc3\x94/O/go;    # O circumflex
        $string =~ s/\xc3\x95/O/go;    # O tilde
        $string =~ s/\xc3\x96/Oe/go;   # O uml

        $string =~ s/\xc3\xb9/u/go;    # u grave
        $string =~ s/\xc3\xba/u/go;    # u acute
        $string =~ s/\xc3\xbb/u/go;    # u circumflex
        $string =~ s/\xc3\xbc/ue/go;   # u uml
        $string =~ s/\xc5\xaf/u/go;    # u ring above

        $string =~ s/\xc3\x99/U/go;    # U grave
        $string =~ s/\xc3\x9a/U/go;    # U acute
        $string =~ s/\xc3\x9b/U/go;    # U circumflex
        $string =~ s/\xc3\x9c/Ue/go;   # U uml
        $string =~ s/\xc5\xae/U/go;    # U ring above

        $string =~ s/\xc5\x99/r/go;    # r caron
        $string =~ s/\xc5\x98/R/go;    # R caron

        $string =~ s/\xc3\x9f/ss/go;   # sharp s
        $string =~ s/\xc5\x9b/s/go;    # s acute
        $string =~ s/\xc5\xa1/s/go;    # s caron
        $string =~ s/\xc5\x9a/S/go;    # S acute
        $string =~ s/\xc5\xa0/S/go;    # S caron

        $string =~ s/\xc5\xa5/t/go;    # t caron
        $string =~ s/\xc5\xa4/T/go;    # T caron

        $string =~ s/\xc3\xb1/n/go;    # n tilde
        $string =~ s/\xc5\x84/n/go;    # n acute
        $string =~ s/\xc5\x88/n/go;    # n caron
        $string =~ s/\xc5\x83/N/go;    # N acute
        $string =~ s/\xc5\x87/N/go;    # N caron

        $string =~ s/\xc3\xbe/y/go;    # y acute
        $string =~ s/\xc3\xbf/y/go;    # y uml

        $string =~ s/\xc3\xac/i/go;    # i grave
        $string =~ s/\xc3\xab/i/go;    # i acute
        $string =~ s/\xc3\xac/i/go;    # i circumflex
        $string =~ s/\xc3\xad/i/go;    # i uml

        $string =~ s/\xc5\x82/l/go;    # l stroke
        $string =~ s/\xc4\xbe/l/go;    # l caron
        $string =~ s/\xc5\x81/L/go;    # L stroke
        $string =~ s/\xc4\xbd/L/go;    # L caron

        $string =~ s/\xc5\xba/z/go;    # z acute
        $string =~ s/\xc5\xb9/Z/go;    # Z acute
        $string =~ s/\xc5\xbc/z/go;    # z dot
        $string =~ s/\xc5\xbb/Z/go;    # Z dot
        $string =~ s/\xc5\xbe/z/go;    # z caron
        $string =~ s/\xc5\xbd/Z/go;    # Z caron
    } else {
        $string =~ s/\xe0/a/go;        # a grave
        $string =~ s/\xe1/a/go;        # a acute
        $string =~ s/\xe2/a/go;        # a circumflex
        $string =~ s/\xe3/a/go;        # a tilde
        $string =~ s/\xe4/ae/go;       # a uml
        $string =~ s/\xe5/a/go;        # a ring above
        $string =~ s/\xe6/ae/go;       # ae
        $string =~ s/\x01\x05/a/go;    # a ogonek

        $string =~ s/\xc0/A/go;        # A grave
        $string =~ s/\xc1/A/go;        # A acute
        $string =~ s/\xc2/A/go;        # A circumflex
        $string =~ s/\xc3/A/go;        # A tilde
        $string =~ s/\xc4/Ae/go;       # A uml
        $string =~ s/\xc5/A/go;        # A ring above
        $string =~ s/\xc6/AE/go;       # AE
        $string =~ s/\x01\x04/A/go;    # A ogonek

        $string =~ s/\xe7/c/go;        # c cedille
        $string =~ s/\x01\x07/C/go;    # c acute
        $string =~ s/\xc7/C/go;        # C cedille
        $string =~ s/\x01\x06/c/go;    # C acute

        $string =~ s/\xe8/e/go;        # e grave
        $string =~ s/\xe9/e/go;        # e acute
        $string =~ s/\xea/e/go;        # e circumflex
        $string =~ s/\xeb/e/go;        # e uml
        $string =~ s/\x01\x19/e/go;    # e ogonek
        $string =~ s/\xc4\x18/E/go;    # E ogonek

        $string =~ s/\xf2/o/go;        # o grave
        $string =~ s/\xf3/o/go;        # o acute
        $string =~ s/\xf4/o/go;        # o circumflex
        $string =~ s/\xf5/o/go;        # o tilde
        $string =~ s/\xf6/oe/go;       # o uml
        $string =~ s/\xf8/oe/go;       # o stroke

        $string =~ s/\xd3/o/go;        # o acute
        $string =~ s/\xf3/O/go;        # O acute

        $string =~ s/\xd2/O/go;        # O grave
        $string =~ s/\xd3/O/go;        # O acute
        $string =~ s/\xd4/O/go;        # O circumflex
        $string =~ s/\xd5/O/go;        # O tilde
        $string =~ s/\xd6/Oe/go;       # O uml

        $string =~ s/\xf9/u/go;        # u grave
        $string =~ s/\xfa/u/go;        # u acute
        $string =~ s/\xfb/u/go;        # u circumflex
        $string =~ s/\xfc/ue/go;       # u uml

        $string =~ s/\xd9/U/go;        # U grave
        $string =~ s/\xda/U/go;        # U acute
        $string =~ s/\xdb/U/go;        # U circumflex
        $string =~ s/\xdc/Ue/go;       # U uml

        $string =~ s/\xdf/ss/go;       # sharp s
        $string =~ s/\x01\x5b/s/go;    # s acute
        $string =~ s/\x01\x5a/S/go;    # S acute

        $string =~ s/\xf1/n/go;        # n tilde
        $string =~ s/\x01\x44/n/go;    # n acute
        $string =~ s/\x01\x43/N/go;    # N acute

        $string =~ s/\xfe/y/go;        # y acute
        $string =~ s/\xff/y/go;        # y uml

        $string =~ s/\xec/i/go;        # i grave
        $string =~ s/\xed/i/go;        # i acute
        $string =~ s/\xee/i/go;        # i circumflex
        $string =~ s/\xef/i/go;        # i uml

        $string =~ s/\x01\x42/l/go;    # l stroke
        $string =~ s/\x01\x41/L/go;    # L stroke

        $string =~ s/\x01\x7a/z/go;    # z acute
        $string =~ s/\x01\x79/Z/go;    # Z acute
        $string =~ s/\x01\x7c/z/go;    # z dot
        $string =~ s/\x01\x7b/Z/go;    # Z dot
    }

    return $string;
}

sub normalizeWikiName {
    my ($this, $name) = @_;

    $name = transliterate($name);

    my $wikiName = '';

    # first, try without forcing each part to be lowercase
    foreach my $part (split(/[^$Foswiki::regex{mixedAlphaNum}]/, $name)) {
        $wikiName .= ucfirst($part);
    }

    # if it isn't a valid WikiWord and there's no homepage of that name yet, then try more agressively to
    # create a proper WikiName
    if (!Foswiki::Func::isValidWikiWord($wikiName) && !Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $wikiName)) {
        $wikiName = '';
        foreach my $part (split(/[^$Foswiki::regex{mixedAlphaNum}]/, $name)) {
            $wikiName .= ucfirst(lc($part));
        }
    }

    return $wikiName;
}

sub normalizeLoginName {
  my ($this, $name) = @_;

  $name =~ s/@.*$//o;    # remove REALM

  $name = transliterate($name);
  $name =~ s/[^$Foswiki::cfg{LoginNameFilterIn}]//;

  return $name;
}

sub cacheUserFromEntry {
    my ($this, $entry) = @_;

    my $uauth = $this->{uauth};
    my $db = $uauth->db();
    my $pid = $this->getPid();
    my $info = '{}';
    #writeDebug("called cacheUserFromEntry()");

    my $dn = $this->fromLdapCharSet($entry->dn());

    # 1. get it
    my $loginName = $entry->get_value($this->{loginAttribute});
    return 0 unless defined $loginName;
    $loginName =~ s/^\s+//o;
    $loginName =~ s/\s+$//o;
    unless ($loginName) {
        writeDebug("no loginName for $dn ... skipping");
        return 0;
    }
    $loginName = $this->fromLdapCharSet($loginName);

    # 2. normalize
    $loginName = $this->processLoginName($loginName);
    return 0 if $this->{excludeMap}{$loginName};

    # Emails
    my $email;
    my $emails;
    @{$emails} = $entry->get_value($this->{mailAttribute});
    if ($emails) {
#    foreach my $email (@$emails) {
#      $email =~ s/^\s+//o;
#      $email =~ s/\s+$//o;
#      my $prevMapping = $data->{"EMAIL2U::$email"};
#      my %emails = ();
#      $emails{$loginName} = $email;
#      $data->{"EMAIL2U::$email"} = join(',', sort keys %emails);
#    }
        $email = (sort map { $this->fromLdapCharSet($_) =~ s#^\s+##r =~ s#\s+$##r } @$emails)[0]; # XXX
    }
    $email = '' unless defined $email;

    my $displayName = $this->{displayNameFormat};
    $displayName =~ s#\$(\w+)#$this->fromLdapCharSet($entry->get_value($1)) || "\$$1"#ge;
    $displayName =~ s#\$\{(\w+)\}#$this->fromLdapCharSet($entry->get_value($1)) || "\$$1"#ge;

    # store extra display fields
    # 
    # 'DisplayAttributes' => 'cn,mail',
    # 'DisplayNameFormat' => '$cn - $mail',
    #
    if ($this->{displayAttributes}) {
        my $extradata = {};
        for my $attr (@{$this->{displayAttributes}}) {
            # Foswiki::Func::writeWarning($attr . '<->' . $this->fromLdapCharSet($entry->get_value($attr)));
            $extradata->{$attr} = $this->fromLdapCharSet($entry->get_value($attr));
        }
        $info = to_json($extradata);
    }

    # Check whether the current user entry is deactivated (flag ACCOUNTDISABLE)
    # SMELL. Applies to Active Directory only
    # See https://support.microsoft.com/en-us/kb/305144
    my $accoundControl = int($entry->get_value('userAccountControl') || 0);
    my $uacDisabled = $accoundControl & 2;
    $uacDisabled = $uacDisabled ? 1 : 0;

    # get old data
    my $cuid = $db->selectrow_array("SELECT cuid FROM users WHERE pid=? AND login_name=?", {}, $pid, $loginName);

    unless ($cuid) {
        # new user
        # 1. compute a new wikiName
        my @wikiName = ();
        foreach my $attr (@{$this->{wikiNameAttributes}}) {
            my $value = $entry->get_value($attr);
            next unless $value;
            $value =~ s/^\s+//o;
            $value =~ s/\s+$//o;
            $value = $this->fromLdapCharSet($value);
            #writeDebug("$attr=$value");
            push @wikiName, $value;
        }
        my $wikiName = join(" ", @wikiName);

        unless ($wikiName) {
            #$wikiName = $loginName;
            #writeDebug("no WikiNameAttributes found for $dn ... deriving WikiName from LoginName: '$wikiName'");
            writeDebug("no WikiNameAttributes found for $dn ... ignoring");
            return 0;
        }

        # 2. rewrite
        my $oldWikiName = $wikiName;
        foreach my $pattern (keys %{$this->{rewriteWikiNames}}) {
            my $subst = $this->{rewriteWikiNames}{$pattern};
            if ($wikiName =~ /^(?:$pattern)$/) {
                my $arg1 = $1;
                my $arg2 = $2;
                my $arg3 = $3;
                my $arg4 = $4;
                my $arg5 = $5;
                $arg1 = '' unless defined $arg1;
                $arg2 = '' unless defined $arg2;
                $arg3 = '' unless defined $arg3;
                $arg4 = '' unless defined $arg4;
                $subst =~ s/\$1/$arg1/g;
                $subst =~ s/\$2/$arg2/g;
                $subst =~ s/\$3/$arg3/g;
                $subst =~ s/\$4/$arg4/g;
                $subst =~ s/\$5/$arg5/g;
                $wikiName = $subst;
                writeDebug("rewriting '$oldWikiName' to '$wikiName' using rule $pattern");
                last;
            }
        }

        # 3. normalize
        if ($this->{normalizeWikiName}) {
            $wikiName = $this->normalizeWikiName($wikiName);
        }

        # 4. aliasing based on WikiName
        my $alias = $this->{wikiNameAliases}{$wikiName};
        if ($alias) {
            writeDebug("using alias $alias for $wikiName");
            $wikiName = $alias;
        }

        $cuid = $uauth->add_user(undef, $pid, {
            email => $email,
            login_name => $loginName,
            wiki_name => $wikiName,
            display_name => $displayName,
            uac_disabled => $uacDisabled
        });
    } else {
        $uauth->update_user(undef , $cuid, {
            email => $email,
            display_name => $displayName,
            uac_disabled => $uacDisabled
        });
    }
    # fake upsert
    $db->begin_work;
    my $oldData = $db->selectall_arrayref("SELECT dn, info FROM users_ldap WHERE pid=? AND login=?", undef, $pid, $loginName);
    my $row = $oldData->[0];
    if($row && @$row) {
        if($row->[0] ne $dn || $row->[1] ne $info) {
            $db->do("UPDATE users_ldap SET dn=?, cuid=?, info=? where pid=? AND login=?", {}, $dn, $cuid, $info, $pid, $loginName);
        }
    } else {
        $db->do("INSERT INTO users_ldap (pid, login, dn, cuid, info) VALUES (?,?,?,?,?)", {}, $pid, $loginName, $dn, $cuid, $info);
    }
    $db->commit;

#  # get primary group
#  if ($this->{primaryGroupAttribute}) {
#    my $groupId = $entry->get_value($this->{primaryGroupAttribute});
#    $this->{_primaryGroup}{$groupId}{$loginName} = 1 if $groupId;    # delayed
#  }

#  my %groupNames = {}; # TODO  map { $_ => 1 } @{$this->getGroupNames($data)};
    #
    #foreach my $groupName (keys %groupNames) {
    #  if (defined $data->{"GROUP2UNCACHEDMEMBERSDN::$groupName"}) {
    #    my $dnList = Foswiki::Sandbox::untaintUnchecked($data->{"GROUP2UNCACHEDMEMBERSDN::$groupName"}) || '';
    #    my @membersDn = split(/\s*;\s*/, $dnList);
    #
    #  LOOP: {
    #      foreach my $memberDn (@membersDn) {
    #        if ($memberDn eq $dn) {
    #
    #          writeDebug("refreshing group $groupName to catch new members");
    #          removeGroupFromCache($this, $groupName, $data);
    #          checkCacheForGroupName($this, $groupName, $data);
    #          last LOOP;
    #        }
    #      }
    #    }
    #  }
    #}
    return 1;
}

sub processLoginName {
    my ( $this, $loginName ) = @_;

    $loginName = lc($loginName) unless $this->{caseSensitiveLogin};
    $loginName = $this->rewriteLoginName($loginName);
    $loginName = $this->normalizeLoginName($loginName) if $this->{normalizeLoginName};

    return $loginName;
}

sub refreshCache {
    my ($this, $mode) = @_;

    return unless $mode;

    $this->{_refreshMode} = $mode;

    my %tempData;

    my $isOk;

    foreach my $userBase (@{$this->{userBase}}) {
        $isOk = $this->refreshUsersCache(\%tempData, $userBase);
        last unless $isOk;
    }

    if ($isOk && $this->{mapGroups}) {
        foreach my $groupBase (@{$this->{groupBase}}) {
            $isOk = $this->refreshGroupsCache(\%tempData, $groupBase);
            last unless $isOk;
        }
    }

    unless ($isOk) {    # we had an error: keep the old cache til the error is resolved
        return 0;
    }

    undef $this->{_refreshMode};

    return 1;
}

sub processLoginData {
    my ($this, $username, $password) = @_;

    my $pid = $this->getPid();
    unless ($pid) {
        return undef;
    }

    my $uauth = Foswiki::UnifiedAuth->new();
    my $db = $uauth->db;

    $username = $this->processLoginName($username);

    my $userinfo = $db->selectrow_hashref("SELECT cuid, wiki_name FROM users WHERE users.login_name=? AND users.pid=?", {}, $username, $pid);
    return undef unless $userinfo;

    my $dn = $db->selectrow_array("SELECT dn FROM users_ldap WHERE login=? AND pid=?", {}, $username, $pid);
    return undef unless $dn;

    $this->makeConfig();
    return undef unless $this->connect($dn, $password);

    return { cuid => $userinfo->{cuid}, data => {} };
}

sub identify {
    my $this = shift;
    my $login = shift;

    $login = $this->processLoginName($login);
    my $db = Foswiki::UnifiedAuth->new()->db;
    my $pid = $this->getPid;
    my $user = $db->selectrow_hashref("SELECT cuid, wiki_name FROM users WHERE users.login_name=? AND users.pid=?", {}, $login, $pid);

    return {cuid => $user->{cuid}, data => {}} if $user;
    return undef;
}
=pod 

---++ getDisplayAttributesOfLogin($login, $data) -> $displayAttributes

returns the login's display attributes as a hashref

=cut

sub getDisplayAttributesOfLogin {
    my ($this, $login, $data) = @_;
    return 0 unless $login;

    my $pid = $this->getPid();
    my $db = Foswiki::UnifiedAuth->new()->db;
    my $dat = $db->selectrow_array("SELECT info FROM users_ldap WHERE pid=? AND login=?", undef, $pid, $login);
    return 0 unless $dat;
    return from_json(Foswiki::Sandbox::untaintUnchecked($dat));
}
1;
