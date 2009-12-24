package Kirin::Plugin::Rsync;
use constant RUNNING_LOW => 3;
use List::Util qw/sum/;
use strict;
use base 'Kirin::Plugin';
sub user_name {"Backups"}

sub view {
    my ($self, $mm) = @_;
    my ($ac) = Kirin::DB::Rsync->search(customer => $mm->{customer});
    my $quota = $self->_quota($mm->{customer});
    $mm->respond("plugins/rsync/view", rsync => $ac, quota => $quota);
}

sub _handle_buy_request {
    my ($self, $customer) = @_;
    # If we already have an account, do nothing
    my ($ac) = Kirin::DB::Rsync->search(customer => $customer);
    return 1 if $ac;
    return 0 if !($ac = $self->_find_free_account($customer));
    $ac->customer($customer); $ac->update;
    return 1;
}

sub _find_free_account {
    my ($self, $customer) = @_;
    # Find me an rsync entry without a customer
    my (@free) = Kirin::DB::Rsync->search_empty();
    if (!@free) {
        Kirin::Utils->email_boss(
            severity => "error",
            customer => $customer,
            context  => "trying to buy rsync space",
            message  => "Couldn't find a free rsync.net account"
        );
        return;
    }
    if (@free <= RUNNING_LOW) {
        Kirin::Utils->email_boss(
            severity => "warning",
            context  => "trying to buy rsync space",
            message  => @free." rsync.net accounts left; please obtain some more"
        );
    } 
    # XXX
    return (sort { $a->last_used <=> $b->last_used } @free)[0];
}

sub _handle_cancel_request {
    my ($self, $customer, $service) = @_;
    my ($ac) = Kirin::DB::Rsync->search(customer => $customer);
    return 1 unless $ac;
    # Does the customer have any other backup quota apart from the one
    # we're deleting? If so, don't scrub them yet.
    if ($self->_quota($customer) - $service->parameter >= 0) {
        return 1;
    }
    $ac->customer(0);
    $ac->update();
    return 1;
}

sub _parse_email {
    my ($self, @lines) = @_;
    for (@lines) {
        if (/Your Sub account, (\d+),.*:\s+(\d+)/) {
            my ($sub, $amount) = @_;
            # Who owns the account?
            my ($ac) = Kirin::DB::Rsync->search(login => $1);
            $ac->last_used($amount);
            $ac->update;
            my $customer = $ac->customer or next;
            my $quota = $self->_quota($customer);
            if ($amount > $quota) { # XXX Check units
                # Calculate the cost, add line to next invoice
            }
            # Send 'em an email
        }
    }
}

sub _setup_db {
Kirin::DB::Rsync->set_sql(empty => q{
SELECT * FROM rsync
WHERE customer IS NULL
OR customer = 0
});
}
1;
