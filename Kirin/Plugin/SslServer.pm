package Kirin::Plugin::SslServer;
use strict;
use base 'Kirin::Plugin';
sub exposed_to     { 0 }
sub name { "ssl_server" }
sub user_name      { "SSL Server" }
sub default_action { "edit" }

Kirin::Plugin::SslServer->relates_to("Kirin::Plugin::Domain");

sub edit {
    my ($self, $mm, $domain) = @_;
    my $r;
    ($domain, $r) = Kirin::DB::Domain->web_retrieve($mm, $domain);
    return $r if $r;

    # Do we have one?
    my ($rec) = Kirin::DB::SslServer->search(domain => $domain);
    if ($mm->param("editing") and $mm->param("on")) {
        if ($rec) {
        } elsif ($self->_can_add_more($mm->{customer})) {
            $rec = Kirin::DB::SslServer->create({ 
                domain => $domain, customer => $mm->{customer}, 
                primary_server => $primary
            });
            $self->_add_todo($mm, configure_server => $domain->domainname);
        } else { 
            $mm->no_more("SSL servers");
        }
    } elsif ($mm->param("editing")) { # Turn it off
        if ($rec) { 
            $rec->delete;
            $self->_add_todo($mm, deconfigure_server => $domain);
            undef $rec;
        }
    }

    $mm->respond("plugins/ssl_server/edit", domain => $domain,
        have_already => $rec
    );
}

sub _setup_db {
    shift->_ensure_table("secondary_dns");
    Kirin::DB::SslServer->has_a(domain => "Kirin::DB::Domain");
    Kirin::DB::SslServer->has_a(customer => "Kirin::DB::Customer");
    # This following line spelt funny for ->_can_add_more reasons
    Kirin::DB::Customer->has_many(secondarydn => "Kirin::DB::SslServer");
}

package Kirin::DB::SslServer;

sub sql { q/
CREATE TABLE IF NOT EXISTS ssl_server (
    id integer primary key not null,
    customer integer,
    domain integer
);
/ }

1;

