package Kirin;
use strict;
use warnings;
use base qw(Class::Data::Inheritable MicroMaypole);
Kirin->mk_classdata("args");
Kirin->args({});
use Kirin::DB;
use Kirin::Utils;
use Authen::Passphrase;
use Authen::Passphrase::MD5Crypt;
use Module::Pluggable require=>1;
our %map = map { $_->name => $_ } Kirin->plugins();
use Plack::Builder;

sub app {
    my ($self, %args) = @_;
    Kirin::DB->setup_db($args{dsn});
    Kirin->args(\%args);

    builder {
      enable 'Session', store => 'File';
      enable "Plack::Middleware::Static",
             path => qr{^/static/}, root => 'templates/';
      $self->SUPER::app(
          model_prefix => "Kirin::Plugin",
          %args
      );
    };
}

sub authenticate {
    my $self = shift;

    # Skip authentication if our plugins say we can - Paypal callbacks etc.
    my (undef, $noun, $verb, @args) = split /\//,  $self->{req}->path;
    $noun =~ s/_(\w)/\U$1/g; my $class = $self->{model_prefix}."::".ucfirst($noun);
    return if UNIVERSAL::isa($class, "Kirin::Plugin") 
                and { map {$_=>1} $class->_skip_auth()}->{$noun};

    my $sess = $self->{req}->env->{"plack.session"};
    if ($self->{req}->path eq "/logout") { $sess->set("user","") }
    if (!$sess->get("user")) {
        if ($self->{req}->path eq "/signup") {
            if (try_to_add_new_user($self)) { 
                $self->{req}->path("/");
            } else { 
                return $self->respond("signup");
            }
        } elsif (!try_to_login($self)) {
            return $self->respond("login");
        }
    }
    $self->{user} = Kirin::DB::User->retrieve($sess->get("user"));
    if (my $cid = $self->{req}->parameters()->{cid}) {
        my $customer = Kirin::DB::Customer->retrieve($cid);
        warn "XXX ACL check here";
        # XXX ACL check here
        $sess->set("customer", $customer->id);
        $self->{customer} = $customer;
    }
    elsif (my $cust = $sess->get("customer")) { 
        $self->{customer} = Kirin::DB::Customer->retrieve($cust);
    }
    $self->{customer} ||= $self->{user}->customer;
    if (!$self->{customer} and !try_to_add_customer($self, $sess)) {
        return $self->respond("add_customer");
    }
    return;
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
        $self->{req}->env->{"plack.session"}->set("customer" => "");
        # This corrects a subtle bug if we've been logged in as someone else
        return 1;
    }
    push @{$self->{messages}}, "Username or password incorrect";
    return 0;
}

sub try_to_add_new_user {
    # XXX Check captcha
    my $self = shift;
    my $params = $self->{req}->parameters();
    # XXX message
    return unless $params->{username} and $params->{password};
    my $user  = Kirin::DB::User->create({ 
        username => $params->{username},
        password => Authen::Passphrase::MD5Crypt->new(
            salt_random => 1,
            passphrase => $params->{password}
        )->as_crypt
    });
    return unless $user; # Already exists - XXX add message to that effect
    $self->{req}->env->{"plack.session"}->set("user" => $user->id);
    $self->{req}->env->{"plack.session"}->set("customer" => "");
    return 1;
}
sub try_to_add_customer {
    my $self = shift;
    my $params = $self->{req}->parameters();
    # Need at least forename and surname and billing address
    # No error because JS validation should have caught it anyway so if
    # we get here the user's being naughty
    return unless $params->{forename} and $params->{surname} 
        and $params->{billing_email};
    # Do more complex validation here if we need it

    my $customer = Kirin::DB::Customer->create({
        map { $_ => $params->{$_} }
        grep { $params->{$_} }
        Kirin::DB::Customer->columns()
    });
    $self->{user}->add_to_customers({ customer => $customer });
    $self->{user}->customer($customer);
    $self->{user}->update();
    my $sess = $self->{req}->env->{"plack.session"};
    $sess->set("customer", $customer->id);
    $self->{customer} = $customer;
    return 1;
}

1;
