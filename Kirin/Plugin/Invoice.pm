package Kirin::Plugin::Invoice;
use base 'Kirin::Plugin';
sub default_action { "list" }
use strict;

sub view {
    my ($self, $mm, @args) = @_;
    my $params = $mm->{req}->parameters();
    my $invoice = Kirin::DB::Invoice->retrieve($args[0]);
    $mm->respond("plugins/invoice/view", invoice => $invoice);
}

sub list {
    my ($self, $mm, $action) = @_;
    my @invoices = $mm->{user}->is_root ? Kirin::DB::Invoice->retrieve_all()
                                        : $mm->{customer}->invoices;
    # XXX Pager
    $mm->respond("plugins/invoice/list", invoices => \@invoices);
}

1;
