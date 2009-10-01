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
    my @ok_domains;
    for (map {$_->domains } $req->session->get("user")->customers) {
        # Can we do 
        push @ok_domains, $_ if Kirin->can_do($req, $action, $_->domainname);
    }
    my $out;
    my $res = HTTP::Engine::Response->new();
    $req->{template}->process('domainlist', { domains => \@ok_domains, action => $action, req => $req, kirin => Kirin->new }, \$out) ?
        $res->body($out)
    : $res->body($req->{template}->error);
    return $res;
}

1;
