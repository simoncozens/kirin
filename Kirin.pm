package Kirin;
use List::Util qw/max/;
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
        relationships => 1,
    );
    require Kirin::DB;
    Kirin::DB::set_up_db();
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
            request_handler => $mw->handler(sub {$_[0]->{template}=$t;handle_request(@_)}),
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
        $req->session->set("user" => $user);
        return 1;
    }

    return 0;
}

sub handle_request {
    my $req = shift;
    my $page;
    my $res = HTTP::Engine::Response->new;
    my (undef, $action, @args) = split /\//,  $req->path;
    $req->{user} = $req->session->get("user");
    if (!$req->{user} and !try_to_login($req)) {
        $page = "login";
    } elsif (exists $map{$action}) { 
        if (!$args[0]) {
            return $map{$action}->target->list($req,$action);
        }
        return $map{$action}->handle($req, @args);
    } elsif (!$action) { 
        $page = "frontpage";
    } else { 
        $page = "handlers/404" 
    }
    Kirin->respond($req, $action, $page);
}

sub respond {
    my ($self, $req, $action, $template, @args) = @_;
    my $out;
    my $res = HTTP::Engine::Response->new();
    $req->{template}->process($template, { 
        @args,
        action => $action, 
        req => $req, 
        kirin => Kirin->new }, \$out) ?
        $res->body($out)
    : $res->body($req->{template}->error);
    return $res;
}

sub its_all_gone_wrong {
    my $self = shift;
    my $res = HTTP::Engine::Response->new();
    $res->body(shift);
    return $res;
}
