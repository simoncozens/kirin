package Kirin::Plugin::Domain;
use strict;
use base 'Kirin::Plugin';
sub default_action { "list" }

sub user_name { "Domains"               } 

sub list {
    my ($self, $mm) = @_;
    $mm->respond("plugins/domain/list", 
            domains => [ $mm->{customer}->domains ],
            relations => [ $self->relations ]
    );
}

sub _setup_db {
    Kirin::DB::Domain->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(domains => "Kirin::DB::Domain");
}

1;
