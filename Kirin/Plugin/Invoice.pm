package Kirin::Plugin::Invoice;
use base 'Kirin::Plugin';
sub default_action { "list" }
use strict;

sub view {
    my ($self, $mm, @args) = @_;
    my $params = $mm->{req}->parameters();
    my $invoice = Kirin::DB::Invoice->retrieve($args[0]);
    $mm->respond("plugins/invoice/view", invoice => $invoice);
}

sub list {
    my ($self, $mm, $action) = @_;
    my @invoices = $mm->{user}->is_root ? Kirin::DB::Invoice->retrieve_all()
                                        : $mm->{customer}->invoices;
    # XXX Pager
    $mm->respond("plugins/invoice/list", invoices => \@invoices);
}

sub _setup_db {
    Kirin::DB::Invoicelineitem->has_a(invoice => "Kirin::DB::Invoice");
    Kirin::DB::Invoice->has_many(invoicelineitems => "Kirin::DB::Invoicelineitem");
    Kirin::DB::Invoice->has_a(customer => "Kirin::DB::Customer");
}

package Kirin::DB::Invoice;
use List::Util qw(sum);
sub total { return sum map {$_->cost } shift->invoicelineitems; }

sub send_all_reminders { 

}
sub dispatch {
    my $self = shift;
    $self->issued(1);
    $self->issuedate(Time::Piece->new());
    my $t = Template->new({ 
        INCLUDE_PATH => Kirin->args->{"email_template_path"} || "templates" 
    }); 
    my $email;
    $t->process("invoice", { invoice => $self }, \$email) or
        Kirin::Utils->email_boss(
            severity => "error",
            customer => $self,
            context  => "trying to send out invoice ".$self->id,
            message  => $t->error
        );
    return unless $email;
    Kirin::Utils->send_email($email);
    $self->update();
}

1;
