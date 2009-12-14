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
}

package Kirin::DB::User;

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

1;

sub my_domains { # All the domains that I can X
    my $self = shift;
    my $action = shift;
    if ($self->is_root) { return Kirin::DB::Domain->retrieve_all }
    my @ok_domains;
    return grep {$self->can_do($action, $_->domainname)}
        map { $_->domains } 
        $self->customers;
}

1;
