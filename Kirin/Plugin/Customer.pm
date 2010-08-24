package Kirin::Plugin::Customer;
use base 'Kirin::Plugin';
sub name { "customer" }
use strict;
use Email::Valid;
my $valid_check = Email::Valid->new(-mxcheck => 1);

sub edit {
    my ($self, $mm, @args) = @_;
    my $customer = $mm->{customer};
    $self->_edit($mm, $customer, {
        email => sub { $valid_check->address( shift ) },
        billing_email => sub { $valid_check->address( shift ) },
        phone => sub { shift =~ /^\+?[\d-\.]+$/ },
        fax   => sub { shift =~ /^\+?[\d-\.]+$/ }
    });
    $mm->respond("plugins/customer/edit", customer => $customer);
}

sub add {
    my ($self, $mm, @args) = @_;
    my $params = $mm->{req}->parameters;
    # XXX This code needs to be folded into Kirin::try_to_add_customer
    if ($params->{forename} and $params->{surname} and $params->{billing_email}) {
        my $customer = Kirin::DB::Customer->create({
            map { $_ => $params->{$_} }
            grep { $params->{$_} }
            Kirin::DB::Customer->columns()
        });
        Kirin::DB::Admin->find_or_create({
            user => $mm->{user}->id,
            customer => $customer->id,
        });
        $mm->{user}->update();
        $mm->{customer} = $customer;
        my $sess = $mm->{req}->env->{"plack.session"};
        $sess->set("customer", $customer->id);
        $mm->respond("plugins/customer/view", customer => $customer);
    } else {
        $mm->respond("add_customer", adding => 1);
    }
}

sub view {
    my ($self, $mm) = @_;
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
        expires => (Time::Piece->new() + Time::Seconds->$duration)
    });

    # Add a line in the guy's next bill
    $self->bill_for($subscription);
    return 1;
}

sub cancel_subscription {
    my ($self, $subscription) = @_;
    $subscription->package->_call_service_handlers(cancel => $self);
    # Find the invoice for this
    my ($lineitem) = Kirin::DB::Invoicelineitem->search( subscription => $subscription);
    if ($lineitem) {
        if ($lineitem->invoice->issued) {
            # This needs to be resolved manually
            Kirin::Utils->email_boss(
                severity => "info",
                customer => $self,
                context  => "Cancelled subscription to ".$subscription->package->name,
                message  => "Service has already been invoiced - refund may need to be processed manually"
            );
        } else {
            # Silently remove it
            $lineitem->delete;
        }
    }
    $subscription->delete;
}

sub renew_subscription {
    my ($self, $subscription) = @_;
    my $package = $subscription->package;
    my $duration = "ONE_".uc $package->duration; # URGH
    (warn "PACKAGE ".$package->name." has illegal duration!"), return
        unless Time::Seconds->can($duration);
    $subscription->expires( $subscription->expires + Time::Seconds->$duration );
    $self->bill_for($subscription);
}

sub bill_for {
    my ($customer, $item) = @_; 
    # Ensure we have an open invoice for this customer
    my ($invoice) = Kirin::DB::Invoice->find_or_create(
        customer => $customer,
        issued => 0,
    );

    # Add the relevant line-item to the invoice
    my ($description, $cost);
    my $subscription;
    if (UNIVERSAL::isa($item, "Kirin::DB::Subscription")) {
        $description = $item->package->name." (expires ".$item->expires.")";
        $cost = $item->package->cost;
        $subscription = $item->id;
    } elsif (UNIVERSAL::isa($item, "Kirin::DB::Package")) { 
        $description = $item->description;
        $cost = $item->cost;
    } else {
        # Assume it's a hashref for when we're providing services
        $description = $item->{description};
        $cost = $item->{cost};
    }
    Kirin::DB::Invoicelineitem->create({
        invoice => $invoice,
        description => $description,
        cost => $cost,
        subscription => $subscription
    });
    if (exists Kirin->args->{send_invoice_now_trigger} and
        $invoice->total > Kirin->args->{send_invoice_now_trigger}) {
        $invoice->dispatch;
    }
    return $invoice;
}

sub find_user { Kirin::DB::User->search(customer => shift->id); }

1;
