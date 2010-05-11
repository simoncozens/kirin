package Kirin::Plugin::DomainName;
use JSON::XS;
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
    my ($self, $mm) = @_;
    # Get a domain name
    my $domain = $mm->param("domainpart");
    my $tld    = $mm->param("tld");
    if (!$domain or !$tld) { 
        return $mm->respond("plugins/domain_name/register");
    }

    $domain =~ s/\.$//;
    if ($domain =~ /\./) { 
        $mm->message("Domain name was malformed");
        return $mm->respond("plugins/domain_name/register");
    }
    my $reg = Kirin->args->{registrar_mapper}->($tld);
    if (!$reg) {
        $mm->message("We don't handle that top-level domain");
        return $mm->respond("plugins/domain_name/register");
    }
    $domain .= ".$tld";

    # Check availability
    my %rv = $self->_get_reghandle($mm, $reg);
    return $rv{response} if exists $rv{response};
    my $r = $rv{reghandle};
    if (!$r->is_available($domain)) {
        $mm->message("That domain is not available; please choose another");
        return $mm->respond("plugins/domain_name/register");
    }

    # Get contact addresses, nameservers and register
    %rv = $self->_get_register_args($mm);
    return $rv{response} if exists $rv{response};
    if ($r->register(domain => $domain, %rv)) {
        $mm->message("Domain registered!");
        Kirin::DB::DomainName->create({
            customer       => $mm->{customer},
            domain         => $domain,
            registrar      => $reg,
            billing        => encode_json($rv{billing}),
            admin          => encode_json($rv{admin}),
            technical      => encode_json($rv{tech}),
            nameserverlist => encode_json($rv{nameservers}),
            expires        => NOW + $rv{duration} * ONE_YEAR # XXX Maybe
        });
        return $mm->respond("plugins/domain_name/list");
    }
}


sub _get_register_args {
    # Give me back: billing, admin, tech, nameservers, duration
    my ($self, $mm) = @_;
    # XXX
}

sub _get_reghandle {
    my ($self, $mm, $reg) = @_;
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
    return reghandle => $r;
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
    my %stuff = $self->_get_reghandle($d->registrar);
    return (response => $stuff{response}) if exists $stuff{response};
    return (object => $d, reghandle => $stuff{reghandle});
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
    domain varchar(255) NOT NULL, 
    registrar varchar(40),
    billing text,
    admin text,
    technical text,
    nameserverlist varchar(255),
    expires datetime
);
/}
1;
