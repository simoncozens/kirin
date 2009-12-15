package Kirin::Plugin::Package;
sub name { "package" }
sub user_name { "Products" }
sub default_action { "list" }

sub list {
    my ($self, $mm, $action) = @_;
    if (my $buy = $mm->{req}->params()->{buyproduct}) {
        my $package =  Kirin::DB::Package->retrieve($buy);
        if ($package and $mm->{customer} and
            $mm->{customer}->buy_package($package)) {
                push @{$mm->{messages}}, "Added ".$package->name." to your account";
        }
    }
    my @packages = Kirin::DB::Package->retrieve_all;
    my %categories = map { $_->category => 1 } @packages;
    $mm->respond("plugins/package/list", 
        packages => \@packages,
        categories => [ keys %categories ]
    );
}

sub _setup_db {
    Kirin::DB::PackageService->has_a(package => "Kirin::DB::Package");
    Kirin::DB::PackageService->has_a(service => "Kirin::DB::Service");
    Kirin::DB::Package->has_many(services => ["Kirin::DB::PackageService" => "service"]);
    Kirin::DB::Subscription->has_a(package => "Kirin::DB::Package");
    Kirin::DB::Subscription->has_a(customer => "Kirin::DB::Service");
    Kirin::DB::Customer->has_many(subscriptions => "Kirin::DB::Subscription");

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

1;
