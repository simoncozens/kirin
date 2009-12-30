use Kirin;
Kirin->app(
    template_path => "templates",
    dsn => "dbi:SQLite:kirin.db",
    base => "http://localhost:5000/",
    paypal_recipient => 'simon@simon-cozens.org',
    enom_reseller_username => "resellid",
    enom_reseller_password => "resellpw",
    amavis_dsn => "dbi:SQLite:amavis.db",
    primary_dns_server => "ns1.mythic-beasts.com",
);
