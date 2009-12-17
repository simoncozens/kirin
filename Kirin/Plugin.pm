package Kirin::Plugin;
use UNIVERSAL::moniker;
sub name { shift->moniker }
sub user_name {
    my $name = shift->name;
    $name =~ s/_(.)/ \U$1/g;
    return ucfirst($name)
}
sub default_action { "view" }
sub _skip_auth { }

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
1;
