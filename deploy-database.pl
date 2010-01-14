$Kirin::just_configuring = 1;
do "kirin.pl"; die $@ if $@;
$Kirin::just_configuring = 0;
use File::Slurp;
Kirin::Plugin->_do_sql(scalar read_file("kirin.sql"));
Kirin::DB->setup_db();
