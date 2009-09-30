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
    my $mw = HTTP::Engine::Middleware->new;
    my %args = @_;
    $mw->install( 'HTTP::Engine::Middleware::Static' => {
        regexp  => qr{^/static/(.+)$},
        docroot => $args{template_path}
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
    my ($action) = split /\//,  $req->path;
    if (exists $map{$action}) { return $map{$action}->handle($req) }
    my $res = HTTP::Engine::Response->new;
    my $out;
    $t->process("handlers/404", { req => $req }, \$out) ?
        $res->body($out)
    : $res->body($t->error);
    $res->status(404); return $res;
}

1;
