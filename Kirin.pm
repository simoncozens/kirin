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
require Module::Pluggable;
our %map;
use Plack::Builder;
use UNIVERSAL::require;

sub app {
    my ($self, %args) = @_;
    Kirin->args(\%args);
    my %plug_options;
    if ($args{plugins}) { 
        $plug_options{only} = $args{plugins};
    } elsif ($args{not_plugins}) {
        $plug_options{except} = $args{not_plugins};
    }
    Module::Pluggable->import(%plug_options);
    # require => 1 in M::P doesn't work with except
    %map = map { $_->require or die "Couldn't load Kirin plugin $_: $@\n"; 
        $_->name => $_ } Kirin->plugins();
    return if $Kirin::just_configuring;
    Kirin::DB->setup_db($args{dsn});

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
    my $path = $self->{req}->path; $path =~ s/^\/+//;
    my ($noun, $verb, @args) = split /\//,  $path;
    $noun =~ s/_(\w)/\U$1/g; my $class = $self->{model_prefix}."::".ucfirst($noun);
    return if UNIVERSAL::isa($class, "Kirin::Plugin") 
                and { map {$_=>1} $class->_skip_auth()}->{$verb};

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
    } elsif ($self->{req}->path eq "/signup") { # But we have signed up!
        $self->{req}->path("/");
    }
    $self->{user} = Kirin::DB::User->retrieve($sess->get("user"));
    if (my $cid = $self->param("cid")) {
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

sub message { my ($mm, @msg) = @_; push @{$mm->{messages}}, @msg }

sub additional_args {
    my $self = shift;
    if (my $user = $self->{user}) {
        return customers => [ $user->my_customers]
    }
    return;
}

sub try_to_login {
    my $self = shift;
    my ($p, $u);
    unless($u = $self->param("username") and $p = $self->param("password")) {
        $self->message("Need to give a username and a password to log in");
        return;
    }
    my ($user) = Kirin::DB::User->search(username => $u);
    if (!$user) {
        # Don't leak more information than necessary
        $self->message("Username or password incorrect");
        return;
    }
    my $real = Authen::Passphrase->from_crypt($user->password);
    if ($real->match($p)) {
        $self->message("Login successful");
        $self->{req}->env->{"plack.session"}->set("user" => $user->id);
        $self->{req}->env->{"plack.session"}->set("customer" => "");
        # This corrects a subtle bug if we've been logged in as someone else
        return 1;
    }
    $self->message("Username or password incorrect");
    return 0;
}

sub try_to_add_new_user {
    # XXX Check captcha
    my $self = shift;
    my ($u, $p);
    $self->message("Need to give a username and a password to register"), return
        unless $u = $self->param("username") 
           and $p = $self->param("password");
    my $user  = eval { Kirin::DB::User->create({ 
        username => $u,
        password => Authen::Passphrase::MD5Crypt->new(
            salt_random => 1,
            passphrase => $p
        )->as_crypt
    }) };
    $self->message("That username has already been taken"), return
        unless $user; # Already exists - XXX add unique constraint to DB
    $self->{req}->env->{"plack.session"}->set("user" => $user->id);
    $self->{req}->env->{"plack.session"}->set("customer" => "");
    return 1;
}
sub try_to_add_customer {
    my $self = shift;
    my $params = $self->{req}->parameters();
    $self->message("Need to give a name and billing address (at least) to register"), return
        unless $params->{forename} and $params->{surname} 
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

sub no_more {
    my ($self, $what) = @_;
    $self->message("You can't add any more $what; do you need to purchase more services?");
}

1;
