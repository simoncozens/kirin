package Kirin::Cronjob::Base::Database;
my $dbh = Kirin::Utils->get_dbh("master_db");

sub create {
    my ($self, $job, $user, $db_id) = @_;
    my $db = Kirin::DB::UserDatabase->retrieve($db_id) or return;
    my $dbh = $self->master_db_handle or return;
    # Looks like you can't do placeholders on a GRANT?
    my $sql = "GRANT ALL PRIVILEGES ON ".$db->name.".* TO ".$db->username.
     "\@localhost IDENTIFIED BY '".$db->password."'";
    $dbh->do($sql)
        or die "Couldn't grant rights on ".$db->name;
    $sql = "GRANT ALL PRIVILEGES ON ".$db->name.".* TO ".$db->username.
     " IDENTIFIED BY '".$db->password."'";
    $dbh->do($sql)
        or die "Couldn't grant rights on ".$db->name;
    $dbh->func("createdb", $db->name, 'admin')
        or die "Couldn't create db ".$db->name;
    return 1;
}

sub drop {
    my ($self, $job, $user, $db_id) = @_;
    my $db = Kirin::DB::UserDatabase->retrieve($db_id) or return;
    my $dbh = $self->master_db_handle or return;
    my $sql = "REVOKE ALL PRIVILEGES ON ".$db->name.".* FROM ".$db->username.
     "\@localhost";
    $dbh->do($sql) or die "Couldn't revoke rights on ".$db->name;
    $sql = "REVOKE ALL PRIVILEGES ON ".$db->name.".* FROM ".$db->username;
    $dbh->do($sql) or die "Couldn't revoke rights on ".$db->name;
    $dbh->func("dropdb", $db->name, 'admin')
        or die "Couldn't drop db ".$db->name;
    $db->delete;
    return 1;
}

1;
