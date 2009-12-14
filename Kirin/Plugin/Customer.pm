package Kirin::Plugin::Customer;
use base 'Kirin::Plugin';
sub name { "customer" }
use strict;

sub edit {
    my ($self, $mm, @args) = @_;
    # XXX ACL Check
    warn "I need to add an ACL check here";
    my $customer = $mm->{customer};
    $self->_edit($mm, $customer);
    $mm->respond("plugins/customer/edit", customer => $customer);
}

sub view {
    my ($self, $mm) = @_;
    # XXX ACL Check
    warn "I need to add an ACL check here";
    my $customer = $mm->{customer};
    $mm->respond("plugins/customer/view", customer => $customer);
}

sub list {
    my ($self, $mm, $action) = @_;
    my @customers; 
    if ($mm->{user}->is_root) { 
        @customers = Kirin::DB::Customer->retrieve_all 
    } else {
        @customers = $mm->{user}->customers;
    }

    $mm->respond("plugins/customer/list", customers => \@customers);
}

1;
