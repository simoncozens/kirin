package Kirin::DB;
use Class::DBI::Loader;

sub setup_db {
    my ($self, $dsn) = @_;
    my $loader = Class::DBI::Loader->new(
        dsn => $dsn,
        namespace => "Kirin::DB",
        options => { AutoCommit => 1 },
        relationships => 1,
    );
    # These are the fundamental relationships
    Kirin::DB::Admin->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Admin->has_a(user => "Kirin::DB::User");
    Kirin::DB::User->has_many(customers => ["Kirin::DB::Admin" => "customer" ]);
    Kirin::DB::Customer->has_many(users => ["Kirin::DB::Admin" => "user"]);
    Kirin::DB::User->has_a(customer => "Kirin::DB::Customer");

    # For everything else, see the individual plugin classes
    for (Kirin->plugins) { $_->can("_setup_db") && $_->_setup_db; }
}

1;
