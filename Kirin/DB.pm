package Kirin::DB;
use Class::DBI::Loader;
our $loader;

sub setup_db {
    my $self = shift;
    $self->setup_main_db();
    # These are the fundamental relationships
    Kirin::DB::Admin->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Admin->has_a(user => "Kirin::DB::User");
    Kirin::DB::User->has_many(customers => ["Kirin::DB::Admin" => "customer" ]);
    Kirin::DB::Customer->has_many(users => ["Kirin::DB::Admin" => "user"]);
    Kirin::DB::User->has_a(customer => "Kirin::DB::Customer");
    # For everything else, see the individual plugin classes
    for (sort { $b->relations <=> $a->relations} 
        Kirin->plugins) { $_->can("_setup_db") && $_->_setup_db; }
}

sub setup_main_db {
    my $self = shift;
    $loader = Class::DBI::Loader->new(
        dsn => Kirin->args->{dsn},
        user => Kirin->args->{database_user},
        password => Kirin->args->{database_password},
        namespace => "Kirin::DB",
        options => { AutoCommit => 1 },
        relationships => 1,
    );

}

1;
