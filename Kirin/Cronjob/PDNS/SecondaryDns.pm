package Kirin::Cronjob::PDNS::SecondaryDns;
my ($dsn, $user, $password) = @ARGV
    or die "You need to supply DSN, username and password";
    # It's cron, so errors will be emailed back to root - no need to send

my $dbh = DBI->connect($dsn, $user, $password)
    || die "Cannot connect to database Error: $!";

sub setup { 
    my ($user, $domain, $rid) = @_;
    my $rec = Kirin::DB::SecondaryDns->retrieve($rid);
    if (!$rec) { return }
    $domain = Kirin::DB::Domain->retrieve($domain);
    if (!$domain) { return } # Domain has disappeared, no longer hosting

    if ($rec->sdns) { 
        # If we already have one, modify it
        $dbh->do("insert into domains (name, master, type, account) 
                values (?,?,?,?)", undef, 
            $domain->domainname, $primary, "SLAVE", $user->username)
        or die "Could not insert domain ".$dbh->errstr;
    } else {
        $dbh->do("delete from domains where name = ? and account = ?",
            undef, $domain->domainname, $user->username);
    }
    if ($rec->mx) {
        # If we have one, modify
    } else { 
        # Delete if necessary
    }
}
