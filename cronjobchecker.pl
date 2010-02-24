do 'kirin.pl';
my $style = shift;
my %needs = (
    webhosting => [ qw/ create delete add_feature remove_feature / ],
    dns => [ qw/ update_server / ],
    database => [ qw/ create drop / ],
    domain => [ qw/ add_hosting / ],
    mail_redirect => [ qw/ update /],
    pop => [ qw/ delete update create /],
    secondary_dns => [ qw/ setup /],
    ssl_server => [ qw/ configure_server deconfigure_server /],


);
for my $plugin (Kirin->plugins) {
    my $ok = 1;
    next unless $needs{$plugin->name};
    print $plugin->name.": ";
    my $package = Kirin->cronjobpackagefor($style, $plugin->name);
    $package->require; 
    if ($@ =~ /an't locate/) { print "$package is missing!\n"; next}
    if ($@) { print "$package is unhappy: $@\n\n"; next }
    for (@{$needs{$plugin->name}}) { unless ($package->can($_)) { 
        print "$package can't $_"; $ok =0;
        print "\n";
    } }
    if ($ok) { print "All OK\n" }
}
