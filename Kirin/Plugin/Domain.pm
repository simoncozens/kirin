package Kirin::Plugin::Domain;
use strict;
use base 'Kirin::Plugin';
use Regexp::Common qw/dns/;

sub default_action { "list" }

sub user_name { "Domains"               } 

sub list {
    my ($self, $mm) = @_;
    my $can_add = $self->_can_add_more($mm->{customer});
    if ($mm->param("adding") and my $domain = $self->_validate($mm, $can_add)) {
        Kirin::DB::Domain->create({
            domainname => $domain, customer => $mm->{customer} 
        });
        $self->_add_todo($mm, addhosting => $domain);
        $mm->message("Your domain has been added and will be available shortly.");
    }
    $mm->respond("plugins/domain/list", 
            domains => [ $mm->{customer}->domains ],
            relations => [ $self->relations ],
            can_add_more => $can_add
    );
}

sub _validate {
    my ($self, $mm, $can_add) = @_;
    if (!$can_add) {
        $mm->message("You cannot add any more domains to your account; please purchase more hosting packages");
        return;
    } 
    my $dn = $mm->param("domainname") or return;
    if (!$dn =~ $RE{'dns'}{'domain'}{-minlables => 2}) {
        $mm->message("Domain name malformed"); return;
    }

    my $res = Net::DNS::Resolver->new;
    my $query = $res->query($dn, "NS");
    if (!$query) {
        $mm->message("Domain '$dn' doesn't have a configured nameserver or isn't registered - do you need to register it first?");
        return;
    }
    # Is it something to do with us?
    if ($self->_is_hosted_by($dn => "MX", Kirin->args->{mx_server})
     or $self->_is_hosted_by($dn => "NS", Kirin->args->{primary_dns_server})
     or $self->_is_hosted_by("www.$dn" => "A", Kirin->args->{hosting_web_server})) {
        return $dn;
    }

    $mm->message("I don't think we host anything for that domain. Email the administrator if you think this is in error.");
    return;
}

sub _setup_db {
shift->_ensure_table("domain");
    Kirin::DB::Domain->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(domains => "Kirin::DB::Domain");
}

package Kirin::DB::Domain;

sub web_retrieve {
    my ($self, $mm, $id) = @_;
    my $domain = $self->retrieve($id);
    if (!$domain) {
        $mm->message("You need to select a domain first");
        return (undef, Kirin::Plugin::Domain->list($mm));
    }
    if ($domain->customer != $mm->{customer}) {
        $mm->message("That's not your domain!");
        return (undef, Kirin::Plugin::Domain->list($mm));
    }
    return ($domain, undef);
}

sub sql {q/
CREATE TABLE IF NOT EXISTS domain (
    id integer primary key not null,
    customer integer,
    domainname varchar(255)
);
/}

1;
