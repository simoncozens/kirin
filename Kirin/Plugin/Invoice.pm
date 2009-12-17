package Kirin::Plugin::Invoice;
use base 'Kirin::Plugin';
sub default_action { "list" }
use strict;

sub view {
    my ($self, $mm, @args) = @_;
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
    Kirin::DB::Invoicelineitem->has_a(subscription => "Kirin::DB::Subscription");
    Kirin::DB::Subscription->might_have(invoicelineitem => "Kirin::DB::Invoicelineitem");
    Kirin::DB::Invoice->has_many(invoicelineitems => "Kirin::DB::Invoicelineitem");
    Kirin::DB::Invoice->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(invoices => "Kirin::DB::Invoice");
}

package Kirin::DB::Invoice;
use List::Util qw(sum);
sub total { return sum map {$_->cost } shift->invoicelineitems; }

sub send_all_reminders { 

}

sub dispatch_all_unissued {
    $_->dispatch for shift->search(issued => 0);
}

sub payment_form {
    my ($self, $mm) = @_;
    # Find us a payment processor
    my $pp = Kirin->args->{payment_processor};
    if (!$pp) { ($pp) = grep { $_->can("_pay_invoice") } Kirin->plugins }
    if (!$pp) {
        Kirin::Utils->email_boss(
            severity => "warning", 
            message => "Can't find a payment processor for invoices"
        );
        return;
    }
    return $pp->_pay_invoice($self, $mm);
}

sub dispatch {
    my $self = shift;
    return if $self->issued() or $self->total <= 0;
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
