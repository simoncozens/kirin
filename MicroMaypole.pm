package MicroMaypole;
use Template;
use Plack::Request;
use Plack::Response;
use strict;
use warnings;

sub app {
    my ($self, %args) = @_;
    if (!$args{model_prefix}) { die "You didn't pass a model prefix!" }
    my $t = Template->new({
        INCLUDE_PATH => $args{templates} || "templates",
        PRE_PROCESS  => "header",
        POST_PROCESS => "footer",
        COMPILE_DIR => $args{compiled_templates},
        COMPILE_EXT => ".ttc"
    });

    sub {
        my $req = Plack::Request->new(shift);
        my $m = $self->new(%args);
        $m->{template_engine} = $t;
        $m->handler($req)->finalize;
    }
}

sub new { my $self = shift; return bless {@_} , $self }

sub authenticate {}

sub do404 { 
    my $res = shift->respond("404handler");
    $res->status(404);  
    $res; 
}

sub default_nounverb {} 

sub handler {
    my ($self, $req) = @_;
    $self->{req} = $req;
    if (my $resp = $self->authenticate()) { return $resp }
    my $path = $req->path; $path =~ s/^\/+//; $req->path($path);
    my ($noun, $verb, @args) = split /\//,  $path;
    if (!$noun) { ($noun, $verb) = $self->default_nounverb }
    $self->{req}{noun} = $noun;
    $self->{req}{verb} = $verb;
    # Convert "noun" to model prefix
    $req->{template} = "$noun/$verb";
    $noun =~ s/_(\w)/\U$1/g; my $class = $self->{model_prefix}."::".ucfirst($noun);
    # Does this class even exist?
    if (!$class->isa("UNIVERSAL")) { return $self->do404(); }
    if ($verb =~ /^_/) { return $self->do404(); } # No you don't
    if (!$class->can($verb)) { 
        warn "Can't call method $verb on class $class" ;
        return $self->do404();
    }
    $class->$verb($self, @args);
}

sub additional_args {}

sub param { my ($self, $name) = @_; $self->{req}->parameters->{$name}; }

sub respond {
    my ($self, $template, @args) = @_;
    my $out;
    $template ||= $self->{req}->{template};
    my $res = Plack::Response->new(200);
    $res->content_type("text/html");
    $self->{template_engine}->process($template, {
        self => $self,
        @args,
        $self->additional_args()
        }, \$out) ? $res->body($out) : $res->body(die $self->{template_engine}->error);
    return $res;
}

1;
