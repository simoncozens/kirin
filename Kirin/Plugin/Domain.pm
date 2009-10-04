package Kirin::Plugin::Domain;
use strict;

sub name      { "domain"                }
sub user_name { "Domains"               } 
sub target    { "Kirin::Plugin::Domain" }

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
