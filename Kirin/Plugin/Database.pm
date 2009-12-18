package Kirin::Plugin::Database;
use constant MAX_USERNAME_LEN => 16;
use constant INFINITY => -1;
use List::Util qw/sum/;
use strict;
use base 'Kirin::Plugin';
sub user_name {"Databases"}

sub list { 
    my ($self, $mm) = @_;
    my @databases = $mm->{customer}->databases;

    if ($mm->param("adding") and my $dbname = $mm->param("dbname")) {
        my $username = $mm->{user}->username;
        $username = "mdb".$mm->{user}->id 
            if length $username > MAX_USERNAME_LEN;
        # All of the things that can possibly go wrong
        my ($dbp1, $dbp2) = ($mm->param("pass1"), $mm->param("pass2"));
        my $db;
        if (!$self->_can_add_more($mm->{customer})) { # No can do
            $mm->message("You cannot add any more databases to your account; please purchase more database quota");
        } elsif ($dbname !~ /^\w+$/) { 
            $mm->message("The database name should consist only of alphanumeric characters");
        } elsif (!$dbp1) { 
            $mm->message("You need to supply a database password");
        } elsif ($dbp1 ne $dbp2) { 
            $mm->message("Passwords don't match");
        } elsif (Kirin::DB::Database->search(name => $dbname)) {
            $mm->message("That name is already taken; please choose another");
        } elsif (
               $db = Kirin::DB::Database->create({
                    customer => $mm->{customer},
                    name => $dbname,
                    username => $username,
                    password => $dbp1
                }) and $db->create_on_backend()){ 
            $mm->message("Database created!");
        } else {
            $mm->message("Something went wrong creating the database; the administrator has been informed");
            Kirin::Utils->email_boss(
                severity => "error",
                customer => $mm->{customer},
                context  => "trying to connect to master database",
                message  => "Master database parameter $_[0] not specified in config"
            );
        }
    }
    # XXX Pager
    $mm->respond("plugins/databases/list", databases => \@databases);
}
sub delete { }

sub _handle_cancel_request {
    my ($self, $customer, $service) = @_;
    # If we're out of databases, get someone to (carefully) delete them
}

sub _can_add_more {
    my ($self, $customer) = @_;
    my $quota = $self->_quota($customer);
    return 1 if $quota == INFINITY;
    return $customer->databases->count < $quota;
}

sub _quota {
    my ($self, $customer) = @_;
    return sum
    map { $_->parameter == INFINITY ? (return INFINITY) : $_->parameter } 
    grep { $_->plugin eq "database" } 
    map { $_->package->services } 
    $customer->subscriptions;
}

sub _setup_db { 
    Kirin::DB::Database->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(databases => "Kirin::DB::Customer");
}

package Kirin::DB::Database;

{ 
    our $dbh;
    my $ouch = sub {
        Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to connect to master database",
            message  => "Master database parameter $_[0] not specified in config"
        );
    };
    sub master_db_handle {
        return $dbh if $dbh;
        my ($dsn, $user, $password) = 
            map { Kirin->args->{$_} or ($ouch->($_), return) }
            qw/ master_db_connect master_db_user master_db_password /;
        $dbh = DBI->connect($dsn, $user, $password) ||
            (Kirin::Utils->email_boss(
                severity => "error",
                context  => "trying to connect to master database",
                message  => "Connection failed! ".$DBI::errstr
            ), return);
    }
}

sub create_on_backend {
    my $self = shift;
    my $dbh = $self->master_db_handle or return;
    $dbh->do('grant all privileges on ?.* to ?@localhost identified by ?',
        undef, $self->name, $self->username, $self->password
    ) or 
        (Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to create database ".$self->name,
            customer => $self->customer,
            message  => "Couldn't grant permission! ".$DBI::errstr
        ), return);
    return ! ! $dbh->func( "createdb", $self->name, 'admin' );
}

1;
