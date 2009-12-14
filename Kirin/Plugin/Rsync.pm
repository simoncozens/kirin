package Kirin::Plugin::Rsync;
use List::Util qw/sum/;
use strict;
use base 'Kirin::Plugin';
sub user_name {"Backups"}

sub view {
    my ($self, $mm) = @_;
    my ($ac) = Kirin::DB::Rsync->search(customer => $mm->{customer});
    $mm->respond("plugins/rsync/view", rsync => $ac);
}


sub register_user {
    my ($self, $user, $parameter) = @_;
    # Find me an rsync entry without a customer
}

sub parse_email {
    my ($self, @lines) = @_;
    for (@lines) {
        if (/Your Sub account, (\d+),.*:\s+(\d+)/) {
            my ($sub, $amount) = @_;
            # Who owns the account?
            my ($ac) = Kirin::DB::Rsync->search(login => $1);
            my $customer = $ac->customer;
            if (!$customer) { warn "Sub account $1 doesn't exist!"; next }
            $ac->last_used($amount);
            my $quota = sum map { $_->parameter} 
                            grep { $_->plugin eq "rsync" } 
                            map { $_->package->services } 
                            $customer->subscriptions;
            if ($amount > $quota) { # XXX Check units
                # Calculate the cost, add line to next invoice
            }
            # Send 'em an email
        }
    }
}
1;
