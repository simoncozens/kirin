package Kirin::Plugin::SecondaryDns;
use strict;
use base 'Kirin::Plugin';
sub exposed_to     { 0 }
sub name { "secondary_dns" }
sub user_name      { "Backup DNS" }
sub default_action { "edit" }
use Regexp::Common qw/net/;

Kirin::Plugin::SecondaryDns->relates_to("Kirin::Plugin::Domain");

sub edit {
    my ($self, $mm, $domain) = @_;
    my $r;
    ($domain, $r) = Kirin::DB::Domain->web_retrieve($mm, $domain);
    return $r if $r;

    my ($rec) = Kirin::DB::SecondaryDns->search(domain => $domain);
    $self->_process_form($mm, $domain, $rec) if $mm->param("editing");
    $mm->respond("plugins/secondary_dns/edit", domain => $domain, have => $rec);
}

sub _process_form {
    my ($self, $mm, $domain, $rec) = @_;
    my $on = ($mm->param("mx")||$mm->param("ns"));
    my $primary = $mm->param("primary_server");
    return if !$rec and !$on;
    if (!$rec and $on and !$self->_can_add_more($mm->{customer})) {
        $mm->no_more("backup DNS");
        return;
    } elsif ($mm->param("ns") and $primary !~ /^$RE{net}{IPv4}$/) {
        $mm->message("Primary server doesn't look like an IP address");
        return;
    } 
    if (!$rec) {
        $rec = Kirin::DB::SecondaryDns->create({ 
            domain => $domain, customer => $mm->{customer}, 
            primary_server => $primary,
            sdns => $mm->param("ns"),
            mx   => $mm->param("mx")
        });
    } else {
        $rec->sdns($mm->param("ns"));
        $rec->mx($mm->param("mx"));
        $rec->primary_server($primary);
        $rec->update;
    }
    $self->_add_todo($mm, setup => $rec->id);

}

sub _setup_db {
    shift->_ensure_table("secondary_dns");
    Kirin::DB::SecondaryDns->has_a(domain => "Kirin::DB::Domain");
    Kirin::DB::SecondaryDns->has_a(customer => "Kirin::DB::Customer");
    # This following line spelt funny for ->_can_add_more reasons
    Kirin::DB::Customer->has_many(secondarydn => "Kirin::DB::SecondaryDns");
}

package Kirin::DB::SecondaryDns;

sub sql { q/
CREATE TABLE IF NOT EXISTS secondary_dns (
    id integer primary key not null,
    customer integer,
    domain integer,
    mx integer,
    sdns integer,
    primary_server varchar(255)
);
/ }

1;

