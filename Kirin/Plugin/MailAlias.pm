package Kirin::Plugin::MailAlias;
use base 'Kirin::Plugin';
sub name      { "mail_alias"            }
sub user_name { "Mail Aliases"          } 
sub default_action { "list" }
Kirin::Plugin::MailAlias->relates_to("Kirin::Plugin::Domain");

sub list {
    my ($self, $mm, $domain) = @_;
    my $r;
    ($domain, $r) = Kirin::DB::Domain->web_retrieve($mm, $domain);
    return $r if $r;

    my $alias_file = "/etc/exim4/virtual/".$domain->domainname;
    if ($mm->param("thefile")){ # We have an upload
        open my $alias, ">", $alias_file or 
            return Kirin->its_all_gone_wrong("Couldn't write on alias file\n");
        print $alias $mm->param("thefile");
        close $alias;
        push @{$req->{messages}}, "Alias file saved successfully";
    }
    if (!-r $alias_file) {
        return Kirin->its_all_gone_wrong("Couldn't find alias file\n");
    }
    Kirin->respond($req, $action, "plugins/mail_alias", 
            alias => [ read_alias($alias_file) ],
            domain => $domain,
    );
}

sub read_alias { # Lifted from Mail::Alias but altered to be order-preserving
     my ($file) = @_;
     open my $fh, $file or die "Can't happen: $!"; # Because we used -r
     my $line;
     my @res;
     while (<$fh>) {
        chomp;
        if (/^#/ || /^\s*$/) { push @res, ["comment", $_]; next }
        if(s/^([^:]+)://) {    
            my @resp;
            $group = $1;
            $group =~ s/(\A\s+|\s+\Z)//g;  
            s/(\A[\s,]+|[\s,]+\Z)//g;
            while(length($_)) {
              s/\A([^\"][^ \t,]+|\"[^\"]+\")(\s*,\s*)*//;
              push(@resp,$1);
            }
             push @res, ["alias", $group, \@resp]
         }
     }
     return @res;
}

1;
