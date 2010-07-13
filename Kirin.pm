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
use Storable qw/freeze thaw/;
use Plack::Builder;
use UNIVERSAL::require;

sub app {
    my ($self, %args) = @_;
    Kirin->args(\%args);
    my %plug_options;
    if ($args{plugins}) { 
        for (@{$args{plugins}}) { if (!/::/) { $_ = "Kirin::Plugin::$_" } }
        $plug_options{only} = $args{plugins};
    } elsif ($args{not_plugins}) {
        for (@{$args{not_plugins}}) { if (!/::/) { $_ = "Kirin::Plugin::$_" } }
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

sub save_context {
    my ($self, $sess) = @_;
    # Save request path, CGI params
    $sess->set("context", freeze({ 
        path => $self->{req}->path,
        params => $self->{req}->parameters
    }));
}

sub restore_context {
    my ($self, $sess) = @_;
    if (my $context = $sess->get("context")) {
        $context = thaw($context);
        $self->{req}->path($context->{path});
        $self->{req}->parameters($context->{params});
        $sess->set("context", undef);
    }
}

sub ensure_user {
    my ($self, $sess) = @_;
    if (!$sess->get("user")) {
        if ($self->{req}->path eq "/signup") {
            if (!try_to_add_new_user($self)) { 
                return $self->respond("signup");
            }
        } elsif (!try_to_login($self)) {
            $self->save_context($sess);
            return $self->respond("login");
        } else {
            #$self->save_context($sess);
        }
    } elsif ($self->{req}->path eq "/signup") { # But we have signed up!
        $self->{req}->path("/package/list"); 
    }
    $self->{user} = Kirin::DB::User->retrieve($sess->get("user")) 
        or return $self->respond("403handler"); # Done gone screwed up
    return; # OK
}

sub session {
    my $self = shift;
    $self->{req}->env->{"psgi.session"}  ||
    $self->{req}->env->{"plack.session"};
}

sub authenticate {
    my $self = shift;

    # Skip authentication if our plugins say we can - Paypal callbacks etc.
    my $path = $self->{req}->path; $path =~ s/^\/+//;
    my ($noun, $verb, @args) = split /\//,  $path;
    $noun =~ s/_(\w)/\U$1/g; my $class = $self->{model_prefix}."::".ucfirst($noun);
    my $sess = $self->session;
    if ($self->{req}->path eq "/logout") { $sess->set("user","") }

    if ($self->{req}->path eq "/forgot_password") {
        return $self->forgot_password;
    }
    my $redirect = $self->ensure_user($sess); 

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
    return $redirect if $redirect;
    $self->{customer} ||= $self->{user}->customer;
    return if UNIVERSAL::isa($class, "Kirin::Plugin") 
                and { map {$_=>1} $class->_skip_auth()}->{$verb};
    if (!$self->{customer} and !try_to_add_customer($self, $sess)) {
        $self->restore_context($sess);
        $self->save_context($sess);
        return $self->respond("add_customer");
    }
    # If we get here - where were we going?
    $self->restore_context($sess);
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
        $self->session->set("user" => $user->id);
        $self->session->set("customer" => "");
        # This corrects a subtle bug if we've been logged in as someone else
        return 1;
    }
    $self->message("Username or password incorrect");
    return 0;
}

sub forgot_password {
    my $self = shift;
    my ($u, $user);
    if ($u = $self->param("username") and 
        ($user) = Kirin::DB::User->search(username => $u)) {
        my $pw = Kirin::Utils->gen_pass($u);
        $user->set_password($pw);
        Kirin::Utils->templated_email(
           template => "password_reset",
           user => $user,
           password => $pw);
        return $self->respond("password_reset");
    }
    $self->respond("forgot_password");
}

sub try_to_add_new_user {
    # XXX Check captcha
    my $self = shift;
    my ($u, $p);
    $self->message("Need to give a username and a password to register"), return
        unless $u = $self->param("username") 
           and $p = $self->param("password");
    $self->message("That username has already been taken"), return
        if getpwnam($u); # We don't want two "daemon" users, for instance
    my $user  = eval { Kirin::DB::User->create({ 
        username => $u,
        password => Authen::Passphrase::MD5Crypt->new(
            salt_random => 1,
            passphrase => $p
        )->as_crypt
    }) };
    $self->message("That username has already been taken"), return
        unless $user; # Already exists 
    Kirin::DB::Jobqueue->find_or_create({
        plugin => "user",
        method => "setup",
        parameters => $user->id
    });
    $self->session->set("user" => $user->id);
    $self->session->set("customer" => "");
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
    my $sess = $self->session;
    $sess->set("customer", $customer->id);
    $self->{customer} = $customer;
    return 1;
}

sub no_more {
    my ($self, $what) = @_;
    $self->message("You can't add any more $what; do you need to purchase more services?");
}

sub cronjobpackagefor {
    my ($self, $style, $plugin) = @_;
    return $style->{$plugin} if ref $style;

    $plugin =~ s/_(\w)/\U$1/g;
    "Kirin::Cronjob::${style}::\u${plugin}";
}

sub cronjobhelper {
    my ($self, $style) = @_;
    # Check we can fulfil it
    my @jobs;
    for my $job (Kirin::DB::Jobqueue->retrieve_all) {
        my $method = $job->method;
        my $plugin = $job->plugin;
        my $package = $self->cronjobpackagefor($style, $plugin);
        $package->require;
        if (!$package->can($method)) {
            die "Couldn't require package $package: $@" if $@;
            die "$package can't fulfil method $method!";
        }
    }
    # Now run the jobs
    for my $job (Kirin::DB::Jobqueue->retrieve_all) {
        next unless $job->customer->status eq "ok";
        my ($user) = $job->customer->find_user();
        die "Customer doesn't have a user account!" unless $user;
        my @args = split /:/, $job->parameters;
        my $method = $job->method;
        my $plugin = $job->plugin;
        my $package = $self->cronjobpackagefor($style, $plugin);
        $package->$method($job, $user, @args) and $job->delete;
    }
}   

1;
