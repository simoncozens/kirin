package Kirin::DB;
use Class::DBI::Loader;

sub setup_db {
    my ($self, $dsn) = @_;
    my $loader = Class::DBI::Loader->new(
        dsn => $dsn,
        namespace => "Kirin::DB",
        options => { AutoCommit => 1 },
        relationships => 1,
    );
    Kirin::DB::Admin->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Admin->has_a(user => "Kirin::DB::User");
    Kirin::DB::User->has_many(customers => ["Kirin::DB::Admin" => "customer" ]);
    Kirin::DB::Customer->has_many(users => ["Kirin::DB::Admin" => "user"]);

    Kirin::DB::User->has_a(customer => "Kirin::DB::Customer");

    Kirin::DB::PackageService->has_a(package => "Kirin::DB::Package");
    Kirin::DB::PackageService->has_a(service => "Kirin::DB::Service");
    Kirin::DB::Package->has_many(services => ["Kirin::DB::PackageService" => "service"]);

    Kirin::DB::Subscription->has_a(package => "Kirin::DB::Package");
    Kirin::DB::Subscription->has_a(customer => "Kirin::DB::Service");
    Kirin::DB::Customer->has_many(subscriptions => "Kirin::DB::Subscription");

    Kirin::DB::Invoicelineitem->has_a(invoice => "Kirin::DB::Invoice");
    Kirin::DB::Invoice->has_many(invoicelineitems => "Kirin::DB::Invoicelineitem");
    Kirin::DB::Invoice->has_a(customer => "Kirin::DB::Customer");

    for (Kirin->plugins) { $_->can("setup_db") && $_->setup_db; }
}

package Kirin::DB::User;

sub my_customers {
    my $self = shift;
    return Kirin::DB::Customer->retrieve_all if $self->is_root;
    if ($self->customers->count > 1) { return $self->customers }
    return $self->customer
}

sub is_root {
    my $self = shift;
    if (($acl) = Kirin::DB::Acl->search(user => $self->id, domain => "*", action => "*", yesno => 1)) { return 1 }
}

sub can_do { # Our simple ACL processor
    my ($self, $action, $domain) = @_;
    my $acl;
    return 1 if $self->is_root;
    return 1;
    if (!$action) { # Just see if we can see this domain at all
       return max map { $_->yesno }  Kirin::DB::Acl->search(user => $self, domain => $domain);
    } 
    if (!$domain) { 
       return max map { $_->yesno }  Kirin::DB::Acl->search(user => $self, action => $action);
    } 
    if (($acl) = Kirin::DB::Acl->search(user => $self, domain => $domain, action => $action)) { return $acl->yesno; }
    if (($acl) = Kirin::DB::Acl->search(user => $self, domain => "*", action => $action)) { return $acl->yesno; }
    if (($acl) = Kirin::DB::Acl->search(user => $self, domain => $domain, action => "*")) { return $acl->yesno; }
    if (($acl) = Kirin::DB::Acl->search(user => $self, domain => "*", action => "*")) { return $acl->yesno; }
    return 0;
}

sub my_domains { # All the domains that I can X
    my $self = shift;
    my $action = shift;
    if ($self->is_root) { return Kirin::DB::Domain->retrieve_all }
    my @ok_domains;
    return grep {$self->can_do($action, $_->domainname)}
        map { $_->domains } 
        $self->customers;
}

package Kirin::DB::Package;
sub _call_service_handlers {
    my ($self, $type, $customer) = @_;
    my $method = "_handle_${type}_request";
    my $ok = 1;
    # XXX Start transaction
    for my $service ($self->services) {
        next if !$service->plugin or not exists $Kirin::map{$service->plugin};
        my $klass = $Kirin::map{$service->plugin};
        next unless $klass->can($method);
        if (!$klass->$method($customer, $service->parameter)) {
            $ok = 0; last; 
        }
    }
    if ($ok) { # XXX Commit
    } else {
        # XXX Rollback
    }
    return $ok;
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

package Kirin::DB::Invoice;
use List::Util qw(sum);
sub total { return sum map {$_->cost } shift->invoicelineitems; }

1;

