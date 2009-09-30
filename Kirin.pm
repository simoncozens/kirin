package Kirin;
use Template;
use HTTP::Engine;
use HTTP::Engine::Middleware;
use Module::Pluggable require=>1;
use strict;
use warnings;
use Class::DBI::Loader;
use Authen::Passphrase;

my %map = map { $_->name => $_ } Kirin->plugins();
sub import {
    my $self = shift;
    my %args = @_;
    my $mw = HTTP::Engine::Middleware->new( { method_class => 'HTTP::Engine::Request' });
    my $loader = Class::DBI::Loader->new(
        dsn => $args{dsn},
        namespace => "Kirin::DB",
        options => { AutoCommit => 1 },
        require => 1,
        relationships => 1,
    );
    $mw->install( 'HTTP::Engine::Middleware::Static' => {
        regexp  => qr{^/static/(.+)$},
        docroot => $args{template_path}
    });
    $mw->install( 'HTTP::Engine::Middleware::HTTPSession' => {
        state => {
            class => 'URI',
            args  => {
                session_id_name => 'foo_sid',
            },
        },
        store => {
            class => 'File',
            args => { dir => "/tmp/kirin/"},
        },
    });
    my $t = Template->new({
        INCLUDE_PATH => $args{template_path},
        PRE_PROCESS  => "header",
        POST_PROCESS => "footer",
        COMPILE_DIR => $args{compiled_templates},
        COMPILE_EXT => ".ttc"
    });
    HTTP::Engine->new(
        interface => {
            module => $args{interface},
            args   => { %args },
            request_handler => $mw->handler(sub {handle_request(@_,$t)}),
        },
    )->run;
}

sub new { bless {}, shift } # For templates

sub try_to_login {
    my $req = shift;
    my $params = $req->parameters;
    my ($p, $u);
    return unless $u = $params->{username} and $p = $params->{password};
    my ($user) = Kirin::DB::User->search(username => $u);
    return unless $user;
    my $real = Authen::Passphrase->from_crypt($user->password);
    if ($real->match($p)) {
        $req->session->set("valid" => 1);
        $req->session->set("user" => $u);
        return 1;
    }

    return 0;
}

sub handle_request {
    my $req = shift;
    my $t = shift;
    my $page;
    my $res = HTTP::Engine::Response->new;
    my $out;
    my ($action) = split /\//,  $req->path;
    if (exists $map{$action}) { return $map{$action}->handle($req) }
    if (!$req->session->get("valid") and !try_to_login($req)) {
        $page = "login";
    } elsif (!$action) { 
        $page = "frontpage";
    } else { $page = "handlers/404" }
    $t->process($page, { req => $req, kirin => Kirin->new }, \$out) ?
        $res->body($out)
    : $res->body($t->error);
    return $res;
}

1;

