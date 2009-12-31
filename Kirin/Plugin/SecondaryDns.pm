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

    # Do we have one?
    my ($rec) = Kirin::DB::SecondaryDns->search(domain => $domain);
    if ($mm->param("editing") and $mm->param("on")) {
        if ($rec) {
        } elsif ($self->_can_add_more($mm->{customer})) {
            my $primary = $mm->param("primary_server");
            if ($primary =~ /^$RE{net}{IPv4}$/) {
                $rec = Kirin::DB::SecondaryDns->create({ 
                    domain => $domain, customer => $mm->{customer}, 
                    primary_server => $primary
                });
                $self->_add_todo($mm, add_backup => "$domain:$primary");
            } else {
                $mm->message("Primary server doesn't look like an IP address");
            }
        } else { 
            $mm->message("You can't add any more backup MXes; do you need to purchase more services?");
        }
    } elsif ($mm->param("editing")) { # Turn it off
        if ($rec) { 
            $rec->delete;
            $self->_add_todo($mm, remove_backup => $domain);
            undef $rec;
        }
    }

    $mm->respond("plugins/secondary_dns/edit", domain => $domain,
        have_already => $rec
    );
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
    primary_server varchar(255)
);
/ }

1;

