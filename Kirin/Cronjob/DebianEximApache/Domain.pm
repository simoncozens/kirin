package Kirin::Cronjob::DebianEximApache::Domain;
use User::pwent;

sub add_hosting {
    my $domain = Kirin::DB::Domain->retrieve(shift); return unless $domain;
    my $job    = shift;
    my $user   = shift;                              return unless $user;
    my $dn     = $domain->domainname;
    my $user_ent = getpwnam($user->username);

    # Ensure home dir
    if (!$user_ent) { die "User ".$user->username." isn't set up yet" }
    if (!-d  $user_ent->dir) { die "User ".$user->username." doesn't have a home directory" }

    # Create hostings for www.$domain and $domain
    #Kirin::Plugin::Webhosting->_add_todo({customer => $user->customer}, create => $dn, $dn);
    #Kirin::Plugin::Webhosting->_add_todo({customer => $user->customer}, create => "www.$dn", $dn);

    # Email hosting
    open EMAIL, ">/etc/exim4/virtual/$dn" or die $!;
    my $mail = $user->customer->email || $user->customer->billing_email;
    die $user->username." doesn't have an email address" unless $mail;
    print EMAIL "*: ".$mail."\n";
    close EMAIL;
}

1;
