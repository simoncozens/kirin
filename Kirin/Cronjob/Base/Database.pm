package Kirin::Cronjob::Base::Database;

{
    our $dbh;
    sub master_db_handle {
        return $dbh if $dbh;
        my ($dsn, $user, $password) =
            map { Kirin->args->{$_} or die "$_ not configured" }
            qw/ master_db_connect master_db_user master_db_password /;
        $dbh = DBI->connect($dsn, $user, $password) ||
            die "Connection to master database failed: $DBI::errstr"
    }
}

sub create {
    my ($self, $user, $db_id) = @_;
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
    my ($self, $user, $db_id) = @_;
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
