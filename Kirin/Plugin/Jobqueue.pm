package Kirin::Plugin::Jobqueue;
use base 'Kirin::Plugin';
sub exposed_to { $_[1]->is_root() }
sub name { "jobqueue"; }
sub list { # Oh why not
    
}

package Kirin::DB::Jobqueue;

sub process {
    my $self = shift;


}

1;
