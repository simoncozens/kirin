package Kirin::Plugin::Database;
use constant MAX_USERNAME_LEN => 16;
use strict;
use base 'Kirin::Plugin';
sub user_name      { "Databases" }
sub default_action { "list" }

sub list {
    my ($self, $mm) = @_;
    my @databases = $mm->{customer}->databases;

    if ($mm->param("adding") and my $dbname = $mm->param("dbname")) {
        my $username = $mm->{user}->username;
        $username = "mdb" . $mm->{user}->id
            if length $username > MAX_USERNAME_LEN;

        # All of the things that can possibly go wrong
        my ($dbp1, $dbp2) = ($mm->param("pass1"), $mm->param("pass2"));
        my $db;
        if (!$self->_can_add_more($mm->{customer})) {    # No can do
            $mm->no_more("databases");
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
                    name     => $dbname,
                    username => $username,
                    password => $dbp1
                }) and $db->create_on_backend()) {
            $mm->message("Database created!");
        } else {
            $mm->message("Something went wrong creating the database; the administrator has been informed and will create the database manually.");
            Kirin::Utils->email_boss(
                severity => "error",
                customer => $mm->{customer},
                context  => "trying to connect to master database",
                message  => "We couldn't create database $dbname"
            );
        }
    }

    # XXX Pager
    $mm->respond("plugins/database/list", databases => \@databases,
        addable => $self->_can_add_more($mm->{customer}));
}

sub delete {
    my ($self, $mm, $id) = @_;
    my $db;
    if (!$id or !($db = Kirin::DB::Database->retrieve($id))) {
        return $self->list($mm);
    }
    if ($db->customer->id != $mm->{customer}->id and !$mm->{user}->is_root) {
        $mm->message("You can't drop that database, it's not yours!");
        return $self->list($mm);
    }
    if (!$mm->param("confirmdrop")) {
        return $mm->respond("plugins/database/confirmdrop", database => $db);
    }
    if (!$db->drop_on_backend) {

        # Pretend to the user it was, they don't need to know, and get
        # the admin to drop it manually.
        Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to drop database " . $db->name,
            customer => $mm->{customer},
            message  => "Database couldn't be dropped; please drop it manually."
        );
    }
    $mm->message("Database dropped.");
    $db->delete;
    $self->list($mm);
}

sub _handle_cancel_request {
    my ($self, $customer, $service) = @_;

    # If we're out of databases, get someone to (carefully) delete them
}

sub _setup_db {
    Kirin::DB::Database->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(databases => "Kirin::DB::Database");
}

package Kirin::DB::Database;

{
    our $dbh;
    my $ouch = sub {
        Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to connect to master database",
            message => "Master database parameter $_[0] not specified in config"
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
                message  => "Connection failed! " . $DBI::errstr
            ), return);
    }
}

sub went_wrong {
    my ($self, $verb) = @_;
    Kirin::Utils->email_boss(
        severity => "error",
        context  => "trying to $verb database " . $self->name,
        customer => $self->customer,
        message  => "$verb failed " . $DBI::errstr
    );
}

sub create_on_backend {
    my $self = shift;
    my $dbh = $self->master_db_handle or return;
    $dbh->do('grant all privileges on ? to ? identified by ?',
        undef, $self->name . ".*", $self->username . '@localhost', $self->password)
        or (Kirin::Utils->went_wrong("grant rights"), return);
    $dbh->func("createdb", $self->name, 'admin')
        or (Kirin::Utils->went_wrong("createdb"), return);
    return 1;
}

sub drop_on_backend {
    my $self = shift;
    my $dbh = $self->master_db_handle or return;
    $dbh->do('revoke all privileges on ? to ?',
        undef, $self->name . ".*", $self->username . '@localhost')
        or (Kirin::Utils->went_wrong("revoke rights"), return);
    $dbh->do('revoke all privileges on ? to ?',
        undef, $self->name . ".*", $self->username)
        or (Kirin::Utils->went_wrong("revoke rights"), return);
    $dbh->func("dropdb", $self->name, 'admin')
        or (Kirin::Utils->went_wrong("dropdb"), return);
    return 1;
}

sub sql {q/
CREATE TABLE IF NOT EXISTS database (
    id integer primary key not null,
    customer integer,
    name varchar(255),
    username varchar(16),
    password varchar(255)
);
/}
1;
