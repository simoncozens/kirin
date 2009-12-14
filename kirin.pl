use Kirin;
Kirin->app(
    port => "1978",
    template_path => "templates",
    dsn => "dbi:SQLite:kirin.db"
);
