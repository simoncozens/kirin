package Kirin::Plugin;
use List::Util qw/sum/;
use constant INFINITY => -1;
use UNIVERSAL::moniker;
sub name { shift->moniker }
sub user_name {
    my $name = shift->name;
    $name =~ s/_(.)/ \U$1/g;
    return ucfirst($name)
}
sub default_action { "view" }
sub _skip_auth { }
sub exposed_to { 1 }

my %relations = ();

sub relations { @{ $relations{+shift} || [] } }
sub relates_to {
    my ($self, $parent) = @_;
    push @{$relations{$parent}},
        bless \$self, 'Template::Plugin::Class::Proxy';
}

sub _edit {
    my ($self, $mm, $thing) = @_;
    my $params = $mm->{req}->parameters();
    if ($params->{editing}) {
        for ($thing->columns) { if (my $new = $params->{$_}) {
            $thing->$_($new);
        } }
        $thing->update;
    }
}

sub _can_add_more {
    my ($self, $customer) = @_;
    my $quota = $self->_quota($customer);
    return 1 if $quota == INFINITY;
    no strict;
    my $relation = $self->plural_moniker;
    return $customer->$relation->count < $quota;
}

sub _quota {
    my ($self, $customer) = @_;
    return sum 
    map { $_->parameter == INFINITY ? (return INFINITY) : $_->parameter }
    grep { $_->plugin eq $self->name }
    map { $_->package->services } 
    $customer->subscriptions;
}

1;
