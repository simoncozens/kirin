$Kirin::just_configuring = 1;
do "kirin.pl"; die $@ if $@;
use DBI;
my @plugins = @ARGV; if (!@plugins) { @plugins = Kirin->plugins() }
for (@plugins) {
    my $db_class = $_; $db_class =~ s/Plugin/DB/;
    next unless $db_class->can("sql");
    print "Setting up the database table for ".$_->name."\n";
    my $dbh = DBI->connect(Kirin->args->{dsn});
    $dbh->do($db_class->sql) or die $dbh->errstr;
}
