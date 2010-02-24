package Kirin::Cronjob::UKFSN::MailRedirect;
use strict;
use warnings;
use User::pwent;

our $email_dbh = Kirin::Utils->get_dbh("email_db");

sub update {
    my ($self, $job, $user, $d_id) = @_;
    my $domain = Kirin::DB::Domain->retrieve($d_id) || return;
    $email_dbh->do("delete from emailredirect where user = ? and local like ?",
        undef, $user->username, "%\@".$domain->domainname) 
        || die $email_dbh->errstr;
    for ($domain->redirections) { 
        $email_dbh->do("insert into emailredirect (user, local, remote)
            values (?, ?, ?)", undef, 
            $user->username, $_->local, $_->remote) || die $email_dbh->errstr;
    }
    return 1;
}

1;
