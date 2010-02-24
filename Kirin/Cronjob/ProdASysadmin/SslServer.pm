package Kirin::Cronjob::ProdASysadmin::SslServer;
use base 'Kirin::Cronjob::ProdASysadmin::Prodder';

sub configure_server {
    my ($self, $job, $user, $dn) = @_;
    $self->prod ($job, "You need to set up an SSL server for domain $dn")
}

sub deconfigure_server {
    my ($self, $job, $user, $dn) = @_;
    $self->prod ($job, "You need to decomission the SSL server for domain $dn")
}

1;

