package Kirin::Plugin::MailAlias;
use base 'Kirin::Plugin';
sub name      { "mail_alias"            }
sub user_name { "Mail Aliases"          } 

sub handle {
    my ($self, $req, @args) = @_;
    my $domain = Kirin::DB::Domain->retrieve($args[0]);
    # Should recheck ACL here
    if (!$domain or !$req->{user}->can_do("mail_alias", $domain->domainname)) {
        return Kirin->its_all_gone_wrong("Tried to get around the ACL. Naughty!");
    }
    my $alias_file = "/etc/exim4/virtual/".$domain->domainname;
    if ($req->parameters()->{"thefile"}){ # We have an upload
        open my $alias, ">", $alias_file or 
            return Kirin->its_all_gone_wrong("Couldn't write on alias file\n");
        print $alias $req->parameters()->{"thefile"};
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
