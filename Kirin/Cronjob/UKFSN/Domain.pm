package Kirin::Cronjob::UKFSN::Domain;
use strict;
use warnings;
use User::pwent;

if (!Kirin->args->{email_db_login}) {
    die "You need to supply a email_db_login array in your Kirin configuration";
}
our $email_dbh;
{
    $email_dbh = DBI->connect(@{Kirin->args->{email_db_login}})
        or die "Couldn't connect " . DBI->errstr;
}

sub add_hosting {
    my ($self, $job, $user, $d_id) = @_;
    my $domain = Kirin::DB::Domain->retrieve($d_id); return unless $domain;
    return unless $user;
    my $dn     = $domain->domainname;
    my $user_ent = pwent($user->username)
        || die "User ".$user->username." doesn't exist in the Unix system";

    # Start hosting email
    $email_dbh->do("insert into transport values (?, 'virtual:')",
        undef, $dn) or die "Couldn't insert transport: " . $email_dbh->errstr;

    $email_dbh->do("insert into virtual values (?, ?, ?)",
        undef, $dn, $user->username, $user_ent->uid
    ) or die "Couldn't insert transport: " . $email_dbh->errstr;

    $email_dbh->do("insert into virtual values (?, ?, ?)",
        undef, "\@$dn", $user_ent->dir . "/Maildir/", $user->uid
    ) or die "Couldn't insert transport: " . $email_dbh->errstr;

    # Push some DNS records into Kirin's dns table and kick it
    Kirin::DB::DnsRecord->create({
            domain => $domain,
            name => $_->[0], type => $_->[1], priority => $_->[2],
            ttl => $_->[3], data => $_->[4]
        }) for (
        [ $dn,       "NS",  0, 3600, "ns0.ukpost.com"       ],
        [ $dn,       "NS",  0, 3600, "ns1.ukpost.com"       ],
        [ $dn,       "MX",  5, 3600, "mx1.ukfsn.org."       ],
        [ $dn,       "MX", 10, 3600, "mxbackup.ukpost.com." ],
        [ $dn,       "A",   0, 3600, "77.75.108.9"          ],
        [ "www.$dn", "A",   0, 3600, "77.75.108.8"          ],
        );
    Kirin::Plugin::Dns->_add_todo({customer => $user->customer}, update_server => $domain->id);

    system("sudo /usr/local/bin/add-domain-spool.pl $dn " . $user->username);
}
