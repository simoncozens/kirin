package Kirin::Plugin::Domain;
use strict;
use base 'Kirin::Plugin';

sub user_name { "Domains"               } 

sub handle {
    my ($self, $req, @args) = @_;
}

sub list {
    my ($self, $req, $action) = @_;
    Kirin->respond($req, $action, "plugins/domainlist", 
            domains => [ $req->{user}->my_domains($action) ]
    );
}

1;
