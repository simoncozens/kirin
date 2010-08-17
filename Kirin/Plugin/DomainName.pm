package Kirin::Plugin::DomainName;
use Regexp::Common qw/net/;
use JSON::XS;
use Net::DomainRegistration::Simple;
use List::Util qw/sum/;
use strict;
use base 'Kirin::Plugin';
use Time::Seconds;
sub name      { "domain_name" }
sub default_action { "list" }
sub user_name {"Domain Names"}

my @fieldmap = (
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
);

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
                fields => \@fieldmap
               );
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
    %rv = $self->_get_register_args($mm, 0, $tld_handler, %args);
    return $rv{response} if exists $rv{response};
    if ($r->register(domain => $domain, %rv)) {
        $mm->message("Domain registered!");
        Kirin::DB::DomainName->create({
            customer       => $mm->{customer},
            domain         => $domain,
            registrar      => $tld_handler->registrar,
            tldhandler     => $tld_handler->id,
            billing        => encode_json($rv{billing}),
            admin          => encode_json($rv{admin}),
            technical      => encode_json($rv{technical}),
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
    # Give me back: billing, admin, technical, nameservers, duration
    my ($self, $mm, $just_contacts, $tld_handler, %args) = @_;
    my %rv;
    # Do the initial copy
    for my $field (map { $_->[1] } @{$args{fields}}) {
        for (qw/admin billing technical/) {
            my $answer = $mm->param($_."_".$field);
            $rv{$_}{$field} = $answer;
        }
    }

    if (!$just_contacts) {
        if ($mm->param("usedefaultns")) { 
            $rv{nameservers} = [
                Kirin->args->{primary_dns_server},
                Kirin->args->{secondary_dns_server},
            ]
        } else {
            # Check that they're IP addresses.
            my @ns = map { $mm->param($_) } qw(primary_ns secondary_ns);
            my $ok = 1;
            for (@ns) {
                if (!/^$RE{net}{domain}{-nospace}$/) { 
                    $mm->message("Nameserver is not a valid IP address");
                    $ok = 0;
                }
            }
            if ($ok) { $rv{nameservers} = \@ns }
        }
    }

    # Now do some tidy-up
    my $cmess;
    $rv{admin} = $rv{billing} if $mm->param("copybilling2admin");
    $rv{technical} = $rv{billing}  if $mm->param("copybilling2technical");

    for (qw/admin billing technical/) {
        $rv{$_}{company} ||= "n/a";
        if ($rv{$_}{country} !~ /^([a-z]{2})$/i) { 
            delete $rv{$_}{country};
            $cmess++ || $mm->message("Country should be submitted as a two-letter ISO country code");
        }
        if (!Email::Valid->address($rv{$_}{email})) {
            delete $rv{$_}{email};
            $mm->message("Email address for $_ contact is not valid");
        }
        # Anything else?
    }

    # Final check for all parameters
    for my $field (map { $_->[1] } @{$args{fields}}) {
        for (qw/admin billing technical/) {
            if (! $rv{$_}{$field}) {
                $args{notsupplied}{"${_}_$field"}++;
                $rv{response} = 
                    $just_contacts ? 
                        $mm->respond("plugins/domain_name/change_contacts", %args)
                    :   $mm->respond("plugins/domain_name/register", %args);
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
    my %stuff = $self->_get_reghandle($mm, $d->registrar);
    return (response => $stuff{response}) if exists $stuff{response};
    return (object => $d, reghandle => $stuff{reghandle});
}

sub change_contacts {
    my ($self, $mm, $domainid) = @_;
    my %rv = $self->_get_domain($mm, $domainid);
    return $rv{response} if exists $rv{response};

    my ($domain, $handle) = ($rv{object}, $rv{reghandle});
    my %args = ( fields => \@fieldmap, domain => $domain );

    # Massage existing stuff into oldparams
    for my $ctype (qw/billing admin technical/) {
        my $it = decode_json($rv{object}->$ctype);
        for (@fieldmap) {
            $args{oldparams}{$ctype."_".$_->[1]} = $it->{$_->[1]};
            $mm->{req}->parameters->{$ctype."_".$_->[1]} = $it->{$_->[1]};
        }
    }

    %rv = $self->_get_register_args($mm, 1, $handle, %args);
    use Data::Dumper; warn Dumper(\%rv);
    return $rv{response} if exists $rv{response};

    if ($mm->param("change") and $handle->change_contact(domain => $domain->domain, %rv)) {
        for (qw/billing admin technical/) {
            $domain->$_(encode_json($rv{$_}));
        }
        $domain->update;
        $mm->message("Contact updated successfully");
        return $self->list($mm);
    }
    $mm->respond("plugins/domain_name/change_contacts", %args);
}

sub change_nameservers {
    my ($self, $mm, $domainid) = @_;
    my %rv = $self->_get_domain($mm, $domainid);
    return $rv{response} if exists $rv{response};

    my ($domain, $handle) = ($rv{object}, $rv{reghandle});
    my @current = @{decode_json($domain->nameserverlist)};
    my ($primary, $secondary) = map { $mm->param($_) } qw/primary_ns secondary_ns/;
    if ($mm->param("usedefaultns")) { 
        ($primary, $secondary) = (Kirin->args->{primary_dns_server},
            Kirin->args->{secondary_dns_server});
    }

    if ($primary and $secondary) { 
        # Check 'em
        if ($primary !~ /^$RE{net}{domain}{-nospace}$/
            or $secondary !~ /^$RE{net}{domain}{-nospace}$/) { 
            $mm->message("Nameserver address should be a hostname");
        } elsif ($handle->set_nameservers(domain => $domain->domain,
            nameservers => [ $primary, $secondary ])) {
            $domain->nameserverlist(encode_json([ $primary, $secondary ]));
            $domain->update;
            $mm->message("Nameservers changed");
            return $self->list($mm);
        } else {
            $mm->message("Your request could not be completed");
        }
    }
    $mm->respond("plugins/domain_name/change_nameservers",
        current => \@current,
        domain  => $domain
    );
}

sub renew {
    my ($self, $mm, $domainid) = @_;
    my %rv = $self->_get_domain($mm, $domainid);
    return $rv{response} if exists $rv{response};
    my ($domain, $handle) = ($rv{object}, $rv{reghandle});
    if (!$mm->param("duration")) {
        return $mm->respond("plugins/domain_name/renew", domain => $domain);
    }
    my $years = $mm->param("duration");
    my $price = $domain->tld_handler->price * $years / $domain->tld_handler->duration;
    if ($handle->renew(domain => $domain->domain, years => $years)) {
        $mm->{customer}->bill_for({
            description  => "Renewal of of domain ".$domain->domain." for $years years",
            cost         => $price
        });
        $mm->message("Domain renewed");
        $domain->expires($domain->expires + ONE_YEAR * $years);
        return $self->list($mm);
    }
    # Something went wrong
    $mm->message("Your request could not be processed");
    return $mm->respond("plugins/domain_name/renew", domain => $domain);
}

sub revoke {
    my ($self, $mm, $domainid) = @_;
    my %rv = $self->_get_domain($mm, $domainid);
    return $rv{response} if exists $rv{response};

    my ($domain, $handle) = ($rv{object}, $rv{reghandle});
    if (!$mm->param("confirm")) {
        return $mm->respond("plugins/domain_name/revoke", domain => $domain);
    }
    if ($handle->revoke(domain => $domain->domain)) {
        $domain->delete;
        return $self->list($mm);
    }
    # Something went wrong
    $mm->message("Your request could not be processed");
    return $mm->respond("plugins/domain_name/revoke", domain => $domain);
}
sub _setup_db {
    shift->_ensure_table("domain_name");
    Kirin::DB::DomainName->has_a(tld_handler => "Kirin::DB::TldHandler");
    Kirin::DB::DomainName->has_a(expires => 'Time::Piece',
      inflate => sub { Time::Piece->strptime(shift, "%Y-%m-%d") },
      deflate => 'ymd',
    );
}

sub admin {
    my ($self, $mm) = @_;
    if (!$mm->{user}->is_root) { return $mm->respond("403handler") }
    if ($mm->param("create")) {
        if (!$mm->param("registrar")) {
            $mm->message("Handler must have a registrar");
        } elsif (!$mm->param("tld")) {
            $mm->message("Handler must have a name");
        } else {
            my $handler = Kirin::DB::TldHandler->create({
                map { $_ => $mm->param($_) }
                    qw/tld registrar price duration/
            });
            $mm->message("Handler created") if $handler;
        }
    } elsif (my $id = $mm->param("edittld")) {
        my $handler = Kirin::DB::TldHandler->retrieve($id);
        if ($handler) {
            for (qw/tld registrar price duration/) {
                $handler->$_($mm->param($_));
            }
            $handler->update();
        }
    } elsif (my $id = $mm->param("deletetld")) {
         my $thing = Kirin::DB::TldHandler->retrieve($id);
         if ($thing) { $thing->delete; $mm->message("Handler deleted") }
    }
    my @tlds = Kirin::DB::TldHandler->retrieve_all();   
    $mm->respond("plugins/domain_name/admin", tlds => \@tlds);
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
    tld_handler integer,
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
