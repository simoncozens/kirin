package Kirin::Cronjob::UKFSN::Pop;
use strict;
use warnings;
use User::pwent;
my $dbh = Kirin::Utils->get_dbh("email_db");

sub create {
    my ($self, $job, $user, $domain, $localpart, $pass) = @_;

    my $username = $user->username;
    my $address = "$localpart\@$domain";
    my $homedir = '/users/'.substr($username, 0, 1).'/'.$username;
    my $mailbox  = "$homedir/$domain/$localpart";

    my $madepopbox = `sudo /usr/local/bin/add-popbox.pl $domain $localpart $username`;
    if (!$madepopbox || $madepopbox =~ /ERR/) {
        die "Adding popbox for $localpart\@$domain give error $madepopbox";
    }

    $dbh->do("INSERT INTO virtual VALUES (?,?,?)", undef, 
        $address, $mailbox . "/Maildir/", pwent($username)->uid)
        or die "Couldn't insert into virtual ".$dbh->errstr;

    $dbh->do("INSERT INTO popbox VALUES (?,?,?,?,?)", undef, 
        $domain, $localpart, "{plain}$pass", $mailbox, $username)
        or die "Couldn't insert into popbox ".$dbh->errstr;
}

sub update {
    my ($self, $job, $user, $domain, $localpart, $pass) = @_;

    $dbh->do("UPDATE popbox SET password = ? 
                WHERE local = ? AND domain = ? AND owner = ?", undef,
        "{plain}$pass", $localpart, $domain, $user->username)
        or die "Couldn't update popbox ".$dbh->errstr;
}

sub delete {
    my ($self, $job, $user, $domain, $localpart, $pass) = @_;

    my $del = "delete from popbox where local=? AND domain=? AND user=?";
    $dbh->do($del, undef, $localpart, $domain, $user->username)
        or die "Could not delete from popbox";
    my $del2 = "delete from virtual where address = ?";
    $dbh->do($del, undef, "$localpart\@$domain")
        or die "Could not delete from virtual";
}

1;
