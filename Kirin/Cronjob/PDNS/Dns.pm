package Kirin::Cronjob::PDNS::Dns;
use strict;
use warnings;
if (!Kirin->args->{pdns_connect}) {
    die "You need to supply a pdns_connect array in your Kirin configuration";
}
{ 
    my ($dsn, $user, $password) = @{Kirin->args->{pdns_connect}};
    my $loader = Class::DBI::Loader->new(
        dsn => $dsn, user => $user, password => $password,
        options => {RaiseError => 1, AutoCommit => 0},
        namespace => "DNSDB");
}

sub update_server {
    my ($self, $job, $user, $d_id) = @_;
    my $domain = Kirin::DB::Domain->retrieve($d_id); return unless $domain;
    my @records = $domain->dns_records; return unless @records;

    # Find the domain, create if necessary
    my $dns_domain = DNSDB::Domains->find_or_create(
        name => $domain->domainname,
        type => "NATIVE",
        account => $user->username
    );

    # Remove old records, replace with new.
    $_->delete for DNSDNB::Records->search(domain_id => $dns_domain->id);
    for (@records) { 
        DNSDB::Records->create({
            domain_id => $dns_domain->id,
            name => $_->name,
            type => $_->type,
            content => $_->data,
            ttl => $_->ttl,
            prio => $_->priority
        });
    }
}
