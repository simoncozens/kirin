package Kirin::Plugin::Dns;
use Regexp::Common qw/net dns/;
use Net::DNS qw/rrsort/;
use Email::Valid;
use strict;
use base 'Kirin::Plugin';
sub exposed_to     { 0 }
sub user_name      { "DNS Entries" }
sub default_action { "list" }
my $ourprimary = Kirin->args->{primary_dns_server}
    or die "You need to set primary_dns_server in the Kirin configuration";

use constant SUPPORTED_TYPE => {map { $_ => 1 }
        qw/ A AAAA MX CNAME TXT NS SOA PTR SRV /};
use constant HAS_PRIORITY => {MX => 1, NS => 1};
use constant DEFAULT_TTL => 3600;

Kirin::Plugin::Dns->relates_to("Kirin::Plugin::Domain");

my %validators = (
    A     => $RE{dns}{data}{a},
    MX    => $RE{dns}{data}{mx},
    CNAME => $RE{dns}{data}{cname},
    NS    => $RE{dns}{data}{cname},
    SOA   => $RE{dns}{data}{soa},
    TXT   => qr/.{1,254}/,
    AAAA =>    # You may wish to avert your eyes
        qr/^ ( (?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4} )
        | ( ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)::((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?) )
        | ( ((?:[0-9A-Fa-f]{1,4}:){6,6})(25[0-5]|2[0-4]\d|[0-1]?\d?\d)(\.(25[0-5]|2[0-4]\d|[0-1]?\d?\d)){3} )
        | ( ((?:[0-9A-Fa-f]{1,4}(?::[0-9A-Fa-f]{1,4})*)?)::((?:[0-9A-Fa-f]{1,4}:)*)(25[0-5]|2[0-4]\d|[0-1]?\d?\d)(\.(25[0-5]|2[0-4]\d|[0-1]?\d?\d)){3})$/x,

);

sub list {
    my ($self, $mm, $domain) = @_;
    $domain = Kirin::DB::Domain->retrieve($domain);
    if (!$domain) {
        $mm->message("You need to select a domain first");
        return Kirin::Plugin::Domain->list($mm);
    }
    if ($domain->customer != $mm->{customer}) {
        $mm->message("That's not your domain!");
        return Kirin::Plugin::Domain->list($mm);
    }

    my ($local, $whohosts) = $self->_locally_hosted($domain);
    if ($mm->param("editing") and my $record = $self->_validate($domain, $mm, $local)) {
        my $action;
        if ($mm->param("deleting")) {
            $record->{db_entry}->delete(); $action = "deleted";
        } elsif (my $db_entry = delete $record->{db_entry}) {
            $db_entry->$_($record->{$_}) for keys %$record;
            $db_entry->update(); $action = "updated";
        } else {
            $record->{domain} = $domain->id;
            Kirin::DB::DnsRecord->create($record); $action = "created";
        }

        # Add a todo item to kick the backend
        Kirin::DB::Jobqueue->find_or_create({
            customer   => $mm->{customer},
            plugin     => "dns",
            method     => "update_server",
            parameters => $domain->id
        });
        $mm->message("Your record has been $action and will be updated on the server shortly");
    }
    my @records = $local ? $domain->dns_records : ();
    $mm->respond("plugins/dns/list", records => \@records, domain => $domain,
        locally_hosted => $local, whohosts => $whohosts,
        default_ttl    => DEFAULT_TTL,
        has_priority   => HAS_PRIORITY,
        supported_types => [ keys %{+SUPPORTED_TYPE} ],
    );
}

sub _validate {
    my ($self, $domain, $mm, $local) = @_;
    my $domainname = $domain->domainname;
    if (!$local) {
        $mm->message("We don't host DNS for this domain!");
        return;
    }
    my $name = $mm->param("name");
    if (!$name) { return }
    my $type = $mm->param("type");
    if (!$type) { $mm->message("You must supply a record type"); return; }
    if (!SUPPORTED_TYPE->{$mm->param("type")}) {
        $mm->message("We don't support that type of record"); return;
    }
    $name .= ".$domainname" if $name !~ /$domainname$/;
    if ($name !~ /^$RE{dns}{domain}$/) {
        $mm->message("Entry name malformed"); return;
    }
    my $to_validate = $mm->param("data");
    if ($mm->param("priority")) {
        $to_validate = $mm->param("priority") . " " . $to_validate
    }
    if ($validators{$type} and $to_validate !~ /^$validators{$type}$/) {
        $mm->message("$type record malformed"); return;
    }
    my $id = $mm->param("id");
    my $r;
    if ($id and $r = Kirin::DB::DnsRecord->retrieve($id)
        and $r->domain != $domain) {

        # Probably a filthy hacker but we can't call them that just in case
        $mm->message("That's not your rule."); return;
    }
    return {
        db_entry => $r,
        type     => $type,
        name     => $name,
        ttl      => $mm->param("ttl") || DEFAULT_TTL,
        (HAS_PRIORITY->{$type} ?
                (priority => $mm->param("priority")) : ()
        ),
        data => $mm->param("data")
        }
}

sub _setup_db {
    shift->ensure_table("dns_record");
    Kirin::DB::DnsRecord->has_a(domain => "Kirin::DB::Domain");
    Kirin::DB::Domain->has_many(dns_records => "Kirin::DB::DnsRecord");
}

sub _locally_hosted {
    my ($self, $domain) = @_;
    my $res = Net::DNS::Resolver->new;
    my $query = $res->query($domain->domainname, "NS");
    return unless $query;
    my ($primary) = rrsort("NS", "priority", $query->answer);
    return unless $primary;
    $primary = $primary->nsdname;
    return ($primary eq $ourprimary, $primary);
}

package Kirin::DB::Dns;

sub sql { q/
CREATE TABLE IF NOT EXISTS dns_record (
    id integer primary key not null,
    domain integer,
    name varchar(255),
    type varchar(4),
    priority integer,
    ttl integer,
    data varchar(255)
);
/ }

1;

