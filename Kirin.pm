package Kirin;
use strict;
use warnings;
use base 'MicroMaypole';
use Kirin::DB;
use Authen::Passphrase;
use Module::Pluggable require=>1;
our %map = map { $_->name => $_ } Kirin->plugins();
use Plack::Builder;

sub app {
    my ($self, %args) = @_;
    Kirin::DB->setup_db($args{dsn});

    builder {
      enable 'Session', store => 'File';
      enable "Plack::Middleware::Static",
             path => qr{^/static/}, root => 'templates/';
      $self->SUPER::app(
          model_prefix => "Kirin::Plugin",
          %args
      );
    }
}
sub authenticate {
    my $self = shift;
    my $sess = $self->{req}->env->{"plack.session"};
    if (!$sess->get("user") and !try_to_login($self)) {
        return $self->respond("login");
    }
    $self->{user} = Kirin::DB::User->retrieve($sess->get("user"));
    if (my $cid = $self->{req}->parameters()->{cid}) {
        my $customer = Kirin::DB::Customer->retrieve($cid);
        warn "XXX ACL check here";
        # XXX ACL check here
        $sess->set("customer", $customer->id);
    }
    $self->{customer} = Kirin::DB::Customer->retrieve($sess->get("customer")) || $self->{user}->customer;
    return;
}

sub email_boss {
    warn @_ # XXX
}

sub default_nounverb { qw/customer view/}
sub additional_args {
    my $self = shift;
    if (my $user = $self->{user}) {
        return customers => [ $user->my_customers]
    }
}

sub try_to_login {
    my $self = shift;
    my $params = $self->{req}->parameters;
    my ($p, $u);
    unless($u = $params->{username} and $p = $params->{password}) {
        #push @{$self->{messages}}, "Need to give a username and a password to log in";
        return;
    }
    my ($user) = Kirin::DB::User->search(username => $u);
    if (!$user) {
        # Don't leak more information than necessary
        push @{$self->{messages}}, "Username or password incorrect";
        return;
    }
    my $real = Authen::Passphrase->from_crypt($user->password);
    if ($real->match($p)) {
        push @{$self->{messages}}, "Login successful";
        $self->{req}->env->{"plack.session"}->set("user" => $user->id);
        return 1;
    }
    push @{$self->{messages}}, "Username or password incorrect";
    return 0;
}
