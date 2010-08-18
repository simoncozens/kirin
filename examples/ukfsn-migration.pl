do 'kirin.pl';
my $dsn = shift @ARGV or die "You need to give a database DSN";
my ($user, $pass) = @ARGV;
my $dbh = DBI->connect($dsn, $user, $pass) or die DBI->errstr;

my %aclabel= ('free' => 'Classic',
              'standard' => 'Standard Direct Hosting',
              'hosting' => 'Hosting',
              'premium' => 'Premium Direct Hosting',
          'Enta' => 'ADSL Account',
          'enta' => 'ADSL Account',
          'redirect1' => 'Redirect 1 Domain',
              'redirect10' => 'Redirect 10 Domains',
              'redirect25' => 'Redirect 25 Domains',
              'redirect100' => 'Redirect 100 Domains',
              'redirect0' => 'Redirect Unlimited Domains',
              'backup1' => 'MX/DNS Backup 1 Domain',
              'backup5' => 'MX/DNS Backup 5 Domains',
              'backup20' => 'MX/DNS Backup 20 Domains');

print "Converting members table\n";
sub get_all { $dbh->selectall_arrayref("SELECT * FROM ".shift, { Slice=>{} })}

for my $member (@{ get_all("members") }) {
    my $c = Kirin::DB::Customer->find_or_create({
        map { $_ => $member->{$_} }
            qw/forename surname org address town county country postcode
            phone fax email actype status dob billing_email sms
            accountscode/
    });
    my $u = Kirin::DB::User->find_or_create({
        customer => $c->id,
        username => $member->{username},
        password => Authen::Passphrase::MD5Crypt->new(
            salt_random => 1,
            passphrase => $member->{password}
        )->as_crypt
    });
    Kirin::DB::Admin->find_or_create({ user => $u->id, customer => $c->id });
    # Subscriptions are determined by account type.
}

sub uname2custid {
    my $username = shift;
    my ($u) = Kirin::DB::User->search(username => $username);
    die "A table referenced user $username but I didn't find it in members table" unless $u;
    return $u->customer->id;
}

print "Converting certs table\n";
for my $cert (@{ get_all("certs") }) {
    Kirin::DB::SslCertificate->create({
        customer => uname2custid($db->username),
        domain => $cert->{certCN}, # Not quite the same but close enough
        csr => $cert->{certCSR},
        key_file => $cert->{certKey},
        certificate => $cert->{cert},
    });
}

# charges -> invoice?

sub vat_rate { shift->year == 2009 ? 15 : 17.5 }

print "Converting charges table\n";
for my $ch (@{ get_all("charges") }) {
    my $inv = Kirin::DB::Invoice->create({
        id => $ch->{ref},
        issuedate => $ch->{date},
        paid => $ch->{paid},
    });
    my $date = Time::Piece->strptime($strptime, "%Y-%m-%d");
    my $cost = $ch->{amount} / (1+vat_rate($date)/100);
    Kirin::DB::Invoicelineitem->create({
        invoice => $inv,
        description => $ch->{description},
        cost => $cost
    });
}


print "Converting dbases table\n";
for my $db (@{ get_all("dbases") }) {
    Kirin::DB::UserDatabase->create({
        name => $db->{dbname},
        username => $db->{dbuser},
        password => "",
        customer => uname2custid($db->{username})
    });
}

print "Converting hosting table\n";
my @subdomains = @{ get_all("subdomain") };
for my $h (@{ get_all("hosting") }, @{ get_all("freehosting") }) {
    my $dom = Kirin::DB::Domain->create({
        customer => uname2custid($h->{username}),
        domainname => $h->{domain}
    });
    if ($h->{mail}) { } # We don't need to do anything specific, I don't think

    # Grovel in the subdomains table for hostnames, argh.
    if ($h->{web}) { 
        my @subs = grep { 
            $_->{username} eq $h->{username}
            and $_->{domain} eq $h->{domain}
        } @subdomains;
        for (@subs, {subdomain => "www"}) { 
            Kirin::DB::Webhosting->create({
                domain => $dom->id,
                hostname => $_->{subdomain}
            })
        };
    }
}

# XXX Process this from the email database instead.

#print "Converting mailredirect table\n";
#for my $mr (UKFSN::Mailredirect->retrieve_all) { 
#    my $dom = $mr->local; $dom =~ s/^.*\@//;
#    my ($d) = Kirin::DB::Domain->search(domainname => $dom);
#    if ($d) { 
#        Kirin::DB::UserDatabase->create({
#            domain => $d->id,
#            local => $mr->local,
#            remote => $mr->remote
#        });
#    } else {
#        warn "We don't seem to host $dom but have mail redirects for it!\n";
#}

print "Converting mxbackup table\n";
for my $mx (@{ get_all("mxbackup") }) {
    Kirin::DB::SecondaryDns->create({
        customer => uname2custid($mx->{username}),
        domain => $mx->{domain},
        mx => $mx->{mail},
        sdns => $mx->{dns},
        primary_server => $mx->{primary_ns}
    });
}

# renewals -> subscriptions
# XXX

print "Converting rsyncaccounts table\n";
for my $r (@{ get_all("rsyncaccounts") }) {
    Kirin::DB::Rsync->create({
        customer => uname2custid($r->{username}),
        map { $_ => $r->{$_} } qw/login password host/
    });
}

# Connect to the email database and do that
