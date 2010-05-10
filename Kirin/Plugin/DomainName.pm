package Kirin::Plugin::DomainName;
use Net::DomainRegistration::Simple;
use List::Util qw/sum/;
use strict;
use base 'Kirin::Plugin';
sub user_name {"Domain Names"}

sub list {
    my ($self, $mm) = @_;
    my (@names) = Kirin::DB::DomainName->search(customer => $mm->{customer});
    $mm->respond("plugins/domain_name/list", names => \@names);
}

sub register {

}

sub _get_domain {
    my ($self, $mm, $domainid) = @_;
    my $d = Kirin::DB::DomainName->retrieve($domainid);
    if (!$d) { 
        $mm->message("That domain doesn't exist");
        return ( response => $self->list($mm) );
    }
    if ($d->customer != $mm->{customer}) {
        $mm->message("That's not your domain");
        return ( response => $self->list($mm) );
    }
    my $reg = $d->registrar;
    my %credentials = Kirin->args->{registrar_credentials}{$reg};
    if (!%credentials) {
        $mm->message("Internal error: Couldn't connect to that registrar");
        Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to contact registrar $reg",
            message  => "No credentials found! Set Kirin->args->{registrar_credentials}{$reg}"
        );
        return ( response => $self->list($mm) );
    }

    my $r = Net::DomainRegistration::Simple->new(
        registrar => $reg,
        %credentials
    ) 
    if (!$r) {
        $mm->message("Internal error: Couldn't connect to that registrar");
        Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to contact registrar $reg",
            message  => "Could not connect to registrar"
        );
        return ( response => $self->list($mm) );
    }
    return (object => $d, reghandle => $r);
}

sub change_contacts {
    my ($self, $mm, $domainid) = @_;
    my %rv = $self->_get_domain($mm, $domainid);
    return $rv{response} if exists $rv{response};

}

sub change_nameservers {
    my ($self, $mm, $domainid) = @_;
    my %rv = $self->_get_domain($mm, $domainid);
    return $rv{response} if exists $rv{response};
}

sub _setup_db {
    shift->_ensure_table("domain_name");
    # XXX
}

package Kirin::DB::DomainName;

sub sql{q/
CREATE TABLE IF NOT EXISTS domain_name ( id integer primary key not null,
    customer integer,
    domain varchar(40) NOT NULL, 
    registrar varchar(40),
    billing text,
    admin text,
    technical text,
    nameserverlist varchar(255)
);
/}
1;
