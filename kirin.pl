use Kirin;
Kirin->app(
    template_path => "templates",
    dsn => "dbi:SQLite:kirin.db",
    base => "http://localhost:5000/",
    paypal_recipient => 'simon@simon-cozens.org'
);
