package Kirin::Plugin::Domain;
use strict;
use base 'Kirin::Plugin';

sub user_name { "Domains"               } 

sub list {
    my ($self, $mm) = @_;
    $mm->respond("plugins/domain/list", 
            domains => [ $mm->{customer}->domains ]
    );
}

1;
