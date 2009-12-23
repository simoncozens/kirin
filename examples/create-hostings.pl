use Kirin::DB;
Kirin::DB->setup_db("dbi:SQLite:kirin.db");

my $description = "Our Direct Hosting services are ideal for those who want full service hosting on a domain. The service provides comprehensive Email and Webspace on our Linux servers based in London Docklands.

With a host of powerful features our Direct Hosting account is ideal for those who wish to publish a dynamic and attractive website.

The comprehensive email facilities included with our Direct Hosting account provide everything you need to keep your mailbox safe.";

my $standard = Kirin::DB::Package->create({
    category => "hosting", name => "Standard Direct Hosting",
    description => $description, cost => 52.17, duration => "year"
});

my @standard = (
    ["250MB of Disk Space", "quota", "250"],
    ["", "domain", 1],
    ["Comprehensive PHP Perl & Python installations", "", ""],
    ["MySQL Database", "database", "1"],
    ["Apache .htaccess control", "", ""],
    ["Full Apache access and error logs", "", ""],
    ["Unlimited Email Addresses and POP3 Mailboxes", "email", "0"],
    ["Comprehensive SPAM and Virus Email Filters", "", ""],
    ["All websites and databases backed up offsite daily", "rsync", "250"],
);

$standard->add_to_services({ service => Kirin::DB::Service->find_or_create({
    name => $_->[0],
    plugin => $_->[1],
    parameter => $_->[2]
    })
}) for @standard;

my $premium = Kirin::DB::Package->create({
    category => "hosting", name => "Premium Direct Hosting",
    description => $description, cost => 152.17, duration => "year"
});

my @premium = (
    ["500MB of Disk Space", "quota", "500"],
    ["Support for up to 50 domains", "domain", 50],
    ["Support for SSL Certificate on 1 domain", "ssl", "1"],
    ["Comprehensive PHP Perl & Python installations", "", ""],
    ["MySQL Database", "database", "1"],
    ["Apache .htaccess control", "", ""],
    ["Full Apache access and error logs", "", ""],
    ["Unlimited Email Addresses and POP3 Mailboxes", "email", "0"],
    ["Comprehensive SPAM and Virus Email Filters", "", ""],
    ["All websites and databases backed up offsite daily", "rsync", "500"],
);
$premium->add_to_services({ service => Kirin::DB::Service->find_or_create({
    name => $_->[0],
    plugin => $_->[1],
    parameter => $_->[2]
    })
}) for @premium;

my $backpack = Kirin::DB::Package->create({
    category => "Backup", name => "50G backup pack",
    description => $description, cost => 20.00, duration => "year"
});

$backpack->add_to_services({ service => Kirin::DB::Service->find_or_create({
    name => $_->[0],
    plugin => $_->[1],
    parameter => $_->[2]
    })
}) for ["Additional 50G of backup quota", "quota", "250"];
