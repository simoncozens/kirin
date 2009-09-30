package Kirin;
use Template;
use HTTP::Engine;
use HTTP::Engine::Middleware;
use Module::Pluggable require=>1;
use strict;
use warnings;

my %map = map { $_->name => $_ } Kirin->plugins();
sub import {
    my $self = shift;
    my %args = @_;
    my $mw = HTTP::Engine::Middleware->new( { method_class => 'HTTP::Engine::Request' });
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
            class => 'Test',
            args => { },
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

sub handle_request {
    my $req = shift;
    my $t = shift;
    my $page;
    my $res = HTTP::Engine::Response->new;
    my $out;
    my ($action) = split /\//,  $req->path;
    if (exists $map{$action}) { return $map{$action}->handle($req) }
    if (!$req->session->get("valid")) {
        $page = "login";
    } elsif (!$action) { 
        $page = "frontpage";
    } else { $page = "handlers/404" }
    $t->process($page, { req => $req }, \$out) ?
        $res->body($out)
    : $res->body($t->error);
    return $res;
}

1;
