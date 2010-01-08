package Kirin::Plugin::Jobqueue;
use base 'Kirin::Plugin';
sub exposed_to { $_[1]->is_root() }
sub name { "jobqueue"; }
sub default_action { "list" }
sub list { # Oh why not
    my ($self, $mm) = @_;
    if (!$mm->{user}->is_root) { return $mm->respond("403handler") }
    if ($mm->param("deleting") and 
        my $j = Kirin::DB::Jobqueue->retrieve($mm->param("jid"))) {
        $j->delete; $mm->message("Job deleted");
    }
    return $mm->respond("plugins/jobqueue/list", 
        jobs => [ Kirin::DB::Jobqueue->retrieve_all ]);
}

sub _setup_db {
    Kirin::DB::Jobqueue->has_a(customer => "Kirin::DB::Customer");
}
package Kirin::DB::Jobqueue;

sub process {
    my $self = shift;


}

1;
