package Kirin::Plugin::Domain;
use strict;
use base 'Kirin::Plugin';
sub default_action { "list" }

sub user_name { "Domains"               } 

sub list {
    my ($self, $mm) = @_;
    # Add another hosted domain?
    if ($mm->param("adding")) {
        if (!$self->_can_add_more($mm->{customer})) {    # No can do
        }
    }
    $mm->respond("plugins/domain/list", 
            domains => [ $mm->{customer}->domains ],
            relations => [ $self->relations ]
    );
}

sub _setup_db {
    shift->_ensure_table("domain");
    Kirin::DB::Domain->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(domains => "Kirin::DB::Domain");
}

package Kirin::DB::Domain;

sub sql {q/
CREATE TABLE IF NOT EXISTS domain (
    id integer primary key not null,
    customer integer,
    domainname varchar(255)
);
/}

1;
