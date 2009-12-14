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

1;
