package Kirin::Cronjob::PDNS::SecondaryDns;
my $dbh = Kirin::Utils->get_dbh("pdns_db");

sub setup { 
    my ($self, $job, $user, $domain, $rid) = @_;
    my $rec = Kirin::DB::SecondaryDns->retrieve($rid);
    if (!$rec) { return }
    $domain = Kirin::DB::Domain->retrieve($domain);
    if (!$domain) { return } # Domain has disappeared, no longer hosting

    $dbh->do("delete from domains where name = ? and account = ?",
        undef, $domain->domainname, $user->username);
    if ($rec->sdns) { 
        $dbh->do("insert into domains (name, master, type, account) 
                values (?,?,?,?)", undef, 
            $domain->domainname, $primary, "SLAVE", $user->username)
        or die "Could not insert domain ".$dbh->errstr;
    } 

    # Delete existing
    if ($rec->mx) {
        # Add new
    } 
}
