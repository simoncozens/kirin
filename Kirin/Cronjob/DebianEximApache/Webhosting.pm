package Kirin::Cronjob::DebianEximApache::Webhosting;
use User::pwent;
use File::Path qw/rmtree/;

sub _paths {
    my ($hostname, $domainname, $user) = @_;
    my $user_ent = getpwnam($user->username);
    my $sub;
    die "No hostname" unless $hostname;
    die "No domain name" unless $domainname;
    if ($hostname eq $domainname or $hostname eq "www.$domainname") {
        $sub = "website";
    } else { ($sub) = $hostname =~ /^(\w+)\./; }

    # www.$dn -> ~/$dn/website/ ($sub = "website")
    # $dn     -> ~/$dn/website/ ($sub = "website")
    # foo.$dn -> ~/$dn/foo/     ($sub = first part of hosting name)
    my $user_symlink = $user_ent->dir. "/$domainname/$sub";
    if (!-d $user_ent->dir. "/$domainname") { 
        mkdir $user_ent->dir. "/$domainname";
        chown $user_ent->uid, ($main::gid || -1), $user_ent->dir. "/$domainname";
    } 

    my $real_webhome = '/web/' . $hostname;
    return ( $real_webhome, $user_symlink);
}

sub create {
    my ($self, $job, $user, $hostname, $domain) = @_;
    return unless $user;
    die "No domain?" unless $domain;
    my ($real_webhome, $user_symlink) = _paths($hostname, $domain, $user);

    if ( ! -e $real_webhome) { 
        mkdir $real_webhome; 
        chmod 0705, $real_webhome;
        chown getpwnam($user->username)->uid, ($main::gid || -1), $real_webhome;
    }

    if ( -e $user_symlink and 
        readlink $user_symlink ne $real_webhome) { unlink($user_symlink) }
    if ( ! -e $user_symlink) { symlink($real_webhome, $user_symlink); }

    -f "/etc/apache2/sites-available/template"
        or die "Couldn't open Apache template"; 

    open my $out, ">/etc/apache2/sites-available/$hostname"
    my $tt = Template->new();
    $tt->process("/etc/apache2/sites-available/template",
        { hostname => $hostname,
          user => $user,
          webhome => $real_webhome
        }, $out) || die $tt->error();
}

sub delete {
    my ($self, $job, $user, $hostname, $domain) = @_;
    return unless $user;
    my ($real_webhome, $user_symlink) = _paths($hostname, $domain, $user);

    unlink($user_symlink);
    rmtree($real_webhome); # Archive it? Bah, we've got backups...
}
