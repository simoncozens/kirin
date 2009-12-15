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

1;
