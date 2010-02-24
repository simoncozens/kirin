package Kirin::Cronjob::UKFSN::Webhosting;
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
    my ($self, $job, $user, $hosting_id) = @_;
    return unless $user;
    my $hosting = Kirin::DB::Webhosting->retrieve($hosting_id) or return;
    my $hostname = $hosting->hostname;
    my $domain = $hosting->domain->domainname;
    die "No domain?" unless $domain;
    my ($real_webhome, $user_symlink) = _paths($hostname, $domain, $user);
    if (my ($sym_f) = $hosting->features("symlink")) { 
        my $path = $sym_f->path;
        if ($path =~ /^(\w+|\/)+$/) { # Only process non-naughty links
            $user_symlink = getpwnam($user->username)->dir."/".$path;
        } 
    }

    if ( ! -e $real_webhome) { 
        mkdir $real_webhome; 
        chmod 0705, $real_webhome;
        chown getpwnam($user->username)->uid, ($main::gid || -1), $real_webhome;
    }

    if ( -e $user_symlink and 
        readlink $user_symlink ne $real_webhome) { unlink($user_symlink) }
    if ( ! -e $user_symlink) { symlink($real_webhome, $user_symlink); }
}

sub delete {
    my ($self, $job, $user, $hostname, $domain) = @_;
    return unless $user;
    my ($real_webhome, $user_symlink) = _paths($hostname, $domain, $user);

    unlink($user_symlink);
    rmtree($real_webhome); # Archive it? Bah, we've got backups...
}

sub add_feature    { return 1 } # We don't support features quite yet.
sub remove_feature { return 1 } # But we need to keep the checker happy.

1;
