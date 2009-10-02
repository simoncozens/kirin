package Kirin::DB;

sub set_up_db {
    Kirin::DB::Admin->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Admin->has_a(user => "Kirin::DB::User");
    Kirin::DB::User->has_many(customers => ["Kirin::DB::Admin" => "customer" ]);
    Kirin::DB::Customer->has_many(users => ["Kirin::DB::Domain" => "user"]);
    Kirin::DB::Domain->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(domains => "Kirin::DB::Domain");
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
