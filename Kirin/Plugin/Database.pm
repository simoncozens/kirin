package Kirin::Plugin::Database;
use constant MAX_USERNAME_LEN => 16;
use strict;
use base 'Kirin::Plugin';
sub user_name      { "Databases" }
sub default_action { "list" }

sub list {
    my ($self, $mm) = @_;
    my @databases = $mm->{customer}->databases;
    my $username = $mm->{user}->username;
    $username = "mdb" . $mm->{user}->id
        if length $username > MAX_USERNAME_LEN;

    if ($mm->param("adding") and my $dbname = $mm->param("dbname")) {
        # All of the things that can possibly go wrong
        my ($dbp1, $dbp2) = ($mm->param("pass1"), $mm->param("pass2"));
        my $db;
        $dbname = $username."_".$dbname; # Try to be globally unique
        if (!$self->_can_add_more($mm->{customer})) {    # No can do
            $mm->no_more("databases");
        } elsif ($dbname !~ /^\w+$/) {
            $mm->message("The database name should consist only of alphanumeric characters");
        } elsif (!$dbp1) {
            $mm->message("You need to supply a database password");
        } elsif ($dbp1 ne $dbp2) {
            $mm->message("Passwords don't match");
        } elsif (Kirin::DB::UserDatabase->search(name => $dbname)) {
            $mm->message("That name is already taken; please choose another");
        } elsif (
            $db = Kirin::DB::UserDatabase->create({
                    customer => $mm->{customer},
                    name     => $dbname,
                    username => $username,
                    password => $dbp1
                })
            ) {
            $self->_add_todo($mm, create => $db->id);
            $mm->message("The database will be created shortly");
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
        username => $username,
        addable => $self->_can_add_more($mm->{customer}));
}

sub delete {
    my ($self, $mm, $id) = @_;
    my $db;
    if (!$id or !($db = Kirin::DB::UserDatabase->retrieve($id))) {
        return $self->list($mm);
    }
    if ($db->customer->id != $mm->{customer}->id and !$mm->{user}->is_root) {
        $mm->message("You can't drop that database, it's not yours!");
        return $self->list($mm);
    }
    if (!$mm->param("confirmdrop")) {
        return $mm->respond("plugins/database/confirmdrop", database => $db);
    }
    $self->_add_todo($mm, drop => $db->id);
    $mm->message("The database will be dropped shortly");
    $self->list($mm);
}

sub _handle_cancel_request {
    my ($self, $customer, $service) = @_;

    # If we're out of databases, get someone to (carefully) delete them
}

sub _setup_db {
    shift->_ensure_table("user_database");
    Kirin::DB::UserDatabase->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(databases => "Kirin::DB::UserDatabase");
}

package Kirin::DB::Database;

sub sql {q/
CREATE TABLE IF NOT EXISTS user_database (
    id integer primary key not null,
    customer integer,
    name varchar(255),
    username varchar(16),
    password varchar(255)
);
/}
1;
