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
    if (my $pw = $mm->param("pw1")) {
        if ($pw ne $mm->param("pw2")) {
            $mm->message("Passwords don't match!")
        } elsif ($self->_validate_password($mm, $pw)) {
            $user->set_password($pw);
            $mm->message("Password changed");
        }
    }
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
    $self->id == 1; # For now   
}

sub set_password {
    my ($self, $pw) = @_;
    $self->password(Authen::Passphrase::MD5Crypt->new(
            salt_random => 1,
            passphrase => $pw
        )->as_crypt);
    $self->update;
}

1;
