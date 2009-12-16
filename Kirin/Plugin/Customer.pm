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

sub add {
    my ($self, $mm, @args) = @_;
    my $params = $mm->{req}->parameters;
    if ($params->{forename} and $params->{surname}) {
        my $customer = Kirin::DB::Customer->create({
            map { $_ => $params->{$_} }
            grep { $params->{$_} }
            Kirin::DB::Customer->columns()
        });
        $self->{user}->add_to_customers({ customer => $customer });
        $self->{user}->update();
    }
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

package Kirin::DB::Customer;
use Time::Seconds;
use Time::Piece;

sub buy_package {
    my ($self, $package, $mm) = @_;

    # Set up all our services
    return unless $package->_call_service_handlers(buy => $self);

    # Create a subscription to this customer
    my $duration = "ONE_".uc $package->duration; # URGH
    (warn "PACKAGE ".$package->name." has illegal duration!"), return
        unless Time::Seconds->can($duration);
    
    my $subscription = $self->add_to_subscriptions({
        "package" => $package->id,
        expires => (Time::Piece->new() + Time::Seconds->$duration)->ymd
    });

    # Add a line in the guy's next bill
    $self->bill_for($subscription, $mm);
    return 1;
}

sub cancel_subscription {
    my ($self, $subscription) = @_;
    $subscription->package->_call_service_handlers(cancel => $self);
    $subscription->delete;
}

sub bill_for {
    my ($customer, $item, $mm) = @_; 
    # Ensure we have an open invoice for this customer
    my ($invoice) = Kirin::DB::Invoice->find_or_create(
        customer => $customer,
        issued => 0,
    );

    # Add the relevant line-item to the invoice
    my ($description, $cost);
    if (UNIVERSAL::isa($item, "Kirin::DB::Subscription")) {
        $description = $item->package->name." (expires ".$item->expires.")";
        $cost = $item->package->cost;
    } elsif (UNIVERSAL::isa($item, "Kirin::DB::Package")) { 
        $description = $item->description;
        $cost = $item->cost;
    } else {
        # Assume it's a hashref for when we're providing services
    }
    Kirin::DB::Invoicelineitem->create({
        invoice => $invoice,
        description => $description,
        cost => $cost
    });
    if ($mm and exists $mm->{send_invoice_now_trigger} and
        $invoice->total > $mm->{send_invoice_now_trigger}) {
        $invoice->dispatch;
    }
}

1;
