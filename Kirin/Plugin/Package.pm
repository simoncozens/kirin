package Kirin::Plugin::Package;
sub name { "package" }
sub user_name { "Products" }
sub default_action { "list" }

sub list {
    my ($self, $mm, $action) = @_;
    $mm->respond("plugins/package/list", 
        packages => [ Kirin::DB::Package->retrieve_all ]
    );
}

1;
