package Kirin::Plugin;
use List::Util qw/sum/;
use constant INFINITY => -1;
use UNIVERSAL::moniker;
use UNIVERSAL::require;
use Net::DNS qw/rrsort/;
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
    my ($self, $mm, $thing, $validation) = @_;
    my $params = $mm->{req}->parameters();
    if ($params->{editing}) {
        for ($thing->columns) { if (my $new = $params->{$_}) {
            if ($validation->{$_} and !$validation->{$_}->($new)) {
                $mm->message("Invalid value given for $_, ignored");
            } else { 
                $thing->$_($new);
            }
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

sub _ensure_table {
    my ($self, $table) = @_;
    return if $Kirin::DB::loader->find_class($table);
    warn "Table $table for plugin $self missing, trying to add...\n";
    my $db_class = $self; $db_class =~ s/Plugin/DB/;
    if (!$db_class->can("sql")) { die "Don't know how to set up that table" }
    warn "Setting up the database table for ".$self->name."\n";
    my $dbh = DBI->connect(Kirin->args->{dsn}, Kirin->args->{database_user}, Kirin->args->{database_password});
    for (split /;/, $db_class->sql) { 
        $dbh->do($_) if /\w/;
    }
    Kirin::DB->setup_main_db();
    warn "Table added, carrying on...\n";
}

sub _is_hosted_by {
    my ($self, $thing, $type, $us) = @_;
    my $res = Net::DNS::Resolver->new;
    my $query = $res->query($thing, $type);
    return unless $query;
    my ($primary) = rrsort($type, "priority", $query->answer);
    my $data;
    if    ($type eq "A")     { $data = $primary->address }
    elsif ($type eq "MX")    { $data = $primary->exchange }
    elsif ($type eq "NS")    { $data = $primary->nsdname }
    elsif ($type eq "CNAME") { $data = $primary->cname }
    else { die "Unknown type $type" }
    if (ref $us) {
        my $res = 0;
        for (@$us) { $res = 1 if $data eq $_ }
        return wantarray ? ($res, $data) : $res;
    } else { 
        return wantarray ? ($data eq $us, $data) : $data eq $us;
    }
}


sub _add_todo { 
    my ($self, $mm, $method, $param) = @_;
    Kirin::DB::Jobqueue->find_or_create({
            customer   => $mm->{customer},
            plugin     => $self->name,
            method     => $method,
            parameters => $param
    });
}
1;
