package Kirin::Cronjob::UKFSN::MailRedirect;
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
