package Kirin::Plugin::DomainName;
use JSON::XS;
use Net::DomainRegistration::Simple;
use List::Util qw/sum/;
use strict;
use base 'Kirin::Plugin';
use Time::Seconds;
sub name      { "domain_name" }
sub default_action { "list" }
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
    my %args = (tlds      => [Kirin::DB::TldHandler->retrieve_all],
                oldparams => $mm->{req}->parameters,
                fields => [
                    # Label, field for N::DR::S, field from customer profile
                    ["First Name", "firstname", "forename"],
                    ["Last Name", "lastname", "surname"],
                    ["Company", "company", "org"],
                    ["Address", "address", "address"],
                    ["City", "city", "town"],
                    ["State", "state", "county"],
                    ["Postcode", "postcode", "postcode"],
                    ["Country", "country", "country"],
                    ["Email", "email", "email"],
                    ["Phone", "phone", "phone"],
               ] );
    if (!$domain or !$tld) { 
        return $mm->respond("plugins/domain_name/register", %args);
    }

    $domain =~ s/\.$//;
    if ($domain =~ /\./) { 
        $mm->message("Domain name was malformed");
        return $mm->respond("plugins/domain_name/register", %args);
    }

    my $tld_handler = Kirin::DB::TldHandler->retrieve($tld);
    if (!$tld_handler) {
        $mm->message("We don't handle that top-level domain");
        return $mm->respond("plugins/domain_name/register", %args);
    }
    $domain .= ".".$tld_handler->tld;

    # Check availability
    my %rv = $self->_get_reghandle($mm, $tld_handler->registrar);
    return $rv{response} if exists $rv{response};
    my $r = $rv{reghandle};
    if (!$r->is_available($domain)) {
        $mm->message("That domain is not available; please choose another");
    }

    $args{available} = 1;
    if (!$mm->param("register")) { 
        return $mm->respond("plugins/domain_name/register", %args);
    }

    # Get contact addresses, nameservers and register
    %rv = $self->_get_register_args($mm, $tld_handler, %args);
    return $rv{response} if exists $rv{response};
    if ($r->register(domain => $domain, %rv)) {
        $mm->message("Domain registered!");
        Kirin::DB::DomainName->create({
            customer       => $mm->{customer},
            domain         => $domain,
            registrar      => $tld_handler->registrar,
            billing        => encode_json($rv{billing}),
            admin          => encode_json($rv{admin}),
            technical      => encode_json($rv{tech}),
            nameserverlist => encode_json($rv{nameservers}),
            expires        => Time::Piece->new + $tld_handler->duration * ONE_YEAR 
        });
        $mm->{customer}->bill_for({
            description  => "Registration of domain $domain",
            cost         => $tld_handler->price
        });
        return $self->list($mm);
    }
}

sub _get_register_args {
    # Give me back: billing, admin, tech, nameservers, duration
    my ($self, $mm, $tld_handler, %args) = @_;
    my %rv;
    # Do the initial copy
    for my $field (map { $_->[1] } @{$args{fields}}) {
        for (qw/admin billing tech/) {
            my $answer = $mm->param($_."_".$field);
            $rv{$_}{$field} = $answer;
        }
    }
    # XXX Nameservers, duration

    # Now do some tidy-up
    for (qw/admin billing tech/) {
        $rv{$_}{company} ||= "n/a";
    }
    # XXX

    $rv{admin} = $rv{billing} if $mm->param("copybilling2admin");
    $rv{tech} = $rv{billing}  if $mm->param("copybilling2tech");

    # Final check for all parameters
    for my $field (map { $_->[1] } @{$args{fields}}) {
        for (qw/admin billing tech/) {
            if (! $rv{$_}{$field}) {
                $args{notsupplied}{"${_}_$field"}++;
                $rv{response} = 
                    $mm->respond("plugins/domain_name/register", %args);
            }
        }
    }
    return %rv;
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
    );
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
    Kirin::DB::DomainName->has_a(expires => 'Time::Piece',
      inflate => sub { Time::Piece->strptime(shift, "%Y-%m-%d") },
      deflate => 'ymd',
    );
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

CREATE TABLE IF NOT EXISTS tld_handler ( id integer primary key not null,
    tld varchar(20),
    registrar varchar(40),
    price number(5,2),
    duration integer
);
/}
1;
