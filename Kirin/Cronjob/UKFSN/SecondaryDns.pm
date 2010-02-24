package Kirin::Cronjob::UKFSN::SecondaryDns;
use strict;
use warnings;
use Time::Seconds qw/ONE_YEAR/;
use Time::Piece;
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
            $domain->domainname, $rec->primary, "SLAVE", $user->username)
        or die "Could not insert domain ".$dbh->errstr;
    } 

    $_->delete for Kirin::DB::Mxbackup->search(username => $user->username,
        domain => $domain->domainname);
    if ($rec->mx) {
        Kirin::DB::Mxbackup->create({
            username   => $user->username,
            domain     => $domain->domainname,
            mail       => "Y",
            start_date => Time::Piece->new->ymd,
            end_date   => (Time::Piece->new + ONE_YEAR)->ymd,
            dns        => $rec->sdns,
            primary_ns => $rec->primary
        });
    } 
    return 1;
}

1;
