package Kirin::Plugin::User;
use base 'Kirin::Plugin';
use strict;

sub view { goto &edit }
sub edit {
    my ($self, $mm, @args) = @_;
    my $params = $mm->{req}->parameters();
    # Either: I am root and I'm editing another user, or I'm editing
    # myself
    my $user = $mm->{user}->is_root ? Kirin::DB::User->retrieve($args[0]) 
               : $mm->{user}; 
    $self->_edit($mm, $user);
    $mm->respond("plugins/user/edit", user => $user);
}

sub list {
    my ($self, $mm, $action) = @_;
    # I can't list users if I'm not root; just view myself
    if (!$mm->{user}->is_root) { return $self->edit($mm); }

    $mm->respond("plugins/user/list", 
        users => [ Kirin::DB::User->retrieve_all ]
    );
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
    my $acl;
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

1;
