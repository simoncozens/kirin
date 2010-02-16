package Kirin::Plugin::Package;
use base 'Kirin::Plugin';
sub name { "package" }
sub user_name { "Products" }
sub default_action { "list" }
sub _skip_auth { "list" }

sub buyproduct { goto &list } # It's the same but you have to be logged in

sub list {
    my ($self, $mm) = @_;
    if (my $buy = $mm->{req}->params()->{buyproduct}) {
        my $package =  Kirin::DB::Package->retrieve($buy);
        if ($package and $mm->{customer} and
            $mm->{customer}->buy_package($package)) {
            $mm->message("Added ".$package->name." to your account");
        }
    } elsif (my $renew = $mm->{req}->params()->{renewsubscription}) {
        my $sub =  Kirin::DB::Subscription->retrieve($cancel);
        if (!$sub->customer != $mm->{customer}) {
            $mm->message("That's not your subscription!");
        } else {
            $mm->message("Renewed your subscription to ".$sub->package->name);
            $mm->{customer}->renew_subscription($sub);
        }
    } elsif (my $cancel = $mm->{req}->params()->{cancelsubscription}) {
        my $sub =  Kirin::DB::Subscription->retrieve($cancel);
        if (!$sub->customer != $mm->{customer}) {
            $mm->message("That's not your subscription!");
        } else {
            $mm->message("Removed ".$sub->package->name." from your account");
            $mm->{customer}->cancel_subscription($sub);
        }
    }
    my @packages = Kirin::DB::Package->retrieve_all;
    my %categories = map { $_->category => 1 } @packages;
    $mm->respond("plugins/package/list", 
        packages => \@packages,
        categories => [ keys %categories ]
    );
}

sub edit {
    my ($self, $mm) = @_;
    if (!$mm->{user}->is_root) { return $mm->respond("403handler") }
    if ($mm->param("create")) { 
        if (!$mm->param("category")) {
            $mm->message("Package must have a category");
        } elsif (!$mm->param("name")) { 
            $mm->message("Package must have a name");
        } else {
            my $package = Kirin::DB::Package->create({
                map { $_ => $mm->param($_) }
                    qw/name category cost description duration/
            });
            $mm->message("Package created") if $package;
        }
    } elsif (my $id = $mm->param("editpackage")) {
        my $package = Kirin::DB::Package->retrieve($id);
        if ($package) {
            for (qw/description cost category duration/) {
                $package->$_($mm->param($_));
            }
        }
        $mm->message("Package updated");
    } elsif (my $id = $mm->param("addtopackage")) {
        my $package = Kirin::DB::Package->retrieve($id);
        my $service = Kirin::DB::Service->find_or_create({
            plugin    => $mm->param("plugin"),
            parameter => $mm->param("parameter"),
            name      => $mm->param("name"),
        });
        if ($package) {
            $package->add_to_services($service);
            $mm->message("Service added");
        }
    } elsif (my $id = $mm->param("dropfrompackage")) { 
        # Check for subscriptions first!
        my ($thing) = Kirin::DB::PackageService->search(
            "package" => $mm->param("package"),
            service   => $id
        );
        if ($thing) { $thing->delete; $mm->message("Service removed from package") }
        if (!Kirin::DB::PackageService->search(service => $id)) {
            Kirin::DB::Service->retrieve($id) 
        }
    } elsif (my $id = $mm->param("delete")) {
        my $thing = Kirin::DB::Package->retrieve($id);
        if ($thing) { $thing->delete; $mm->message("Package deleted") }
    }
    return $self->list($mm);
}

sub _setup_db {
    Kirin::DB::PackageService->has_a(package => "Kirin::DB::Package");
    Kirin::DB::PackageService->has_a(service => "Kirin::DB::Service");
    Kirin::DB::Package->has_many(services => ["Kirin::DB::PackageService" => "service"]);
    Kirin::DB::Subscription->has_a(package => "Kirin::DB::Package");
    Kirin::DB::Subscription->has_a(customer => "Kirin::DB::Service");
    Kirin::DB::Subscription->has_a(expires => 'Time::Piece',
      inflate => sub { Time::Piece->strptime(shift, "%Y-%m-%d") },
      deflate => 'ymd',
    );
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
        if (!$klass->$method($customer, $service)) {
            $ok = 0; last; 
        }
    }
    if ($ok) { # XXX Commit
    } else {
        # XXX Rollback
    }
    return $ok;
}

package Kirin::DB::Subscription;
use Time::Piece;
sub expired { shift->expires > Time::Piece->new }

1;
