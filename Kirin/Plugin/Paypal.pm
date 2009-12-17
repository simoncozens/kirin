package Kirin::Plugin::Paypal;
use base 'Kirin::Plugin';
use constant TESTING => 1;
use Business::PayPal;

sub _skip_auth { "ipn" }

sub cancel { 
    my ($self, $mm) = @_;
    my $frob = $mm->{req}->env->{"plack.session"}->get("paypal_frob");
    my ($pp) = Kirin::DB::Paypal->search(magic_frob => $frob);
    if (!$pp) { # Something's gone weird, return them to their customer page
        return Kirin::Plugin::Customer->view($mm);
    }
    my $invoice = $pp->invoice;
    $pp->delete;
    # Back to reviewing the invoice
    $mm->{req}->env->{"plack.session"}->set("paypal_frob", "");
    push @{$mm->{messages}}, "You cancelled the invoice payment";
    $mm->respond("plugins/invoice/view", invoice => $invoice);
}

sub ipn {
    # This is when Paypal calls us back to tell us about the payment
    my ($self, $mm) = @_;
    my $ok = Plack::Response->new(200);
    my $params = $mm->{req}->parameters;
    my $frob = $params->{custom};
    my $paypal = Business::PayPal->new($frob);
    my ($txnstatus, $reason) = $paypal->ipnvalidate($params);
    # Load the invoice; $ok doesn't mean *things* are OK, it means we
    # acknowledge the data Paypal sent us.
    my ($pp) = Kirin::DB::Paypal->search(magic_frob => $frob) or return $ok;
    my $invoice = $pp->invoice or return $ok;
    $pp->status($params->{payment_status});
    $pp->update;
    if ($params->{payment_status} eq "Completed" and
        $params->{payment_gross} eq $invoice->total) {
        $invoice->paid(1);
        $invoice->update();
    } else {
        Kirin::Utils->email_boss(
            severity => "warning",
            customer => $invoice->customer,
            context  => "trying to pay an invoice",
            message  => "Something went wrong with the Paypal payment; please check"
        );
    }
    return $ok;
}

sub return {
    my ($self, $mm) = @_;
    my $frob = $mm->{req}->env->{"plack.session"}->get("paypal_frob");
    $mm->{req}->env->{"plack.session"}->set("paypal_frob", "");
    my ($pp) = Kirin::DB::Paypal->search(magic_frob => $frob);
    my $invoice = $pp->invoice;
    if ($pp->status eq "Completed" and $pp->invoice->paid) {
        push @{$mm->{messages}}, "Paid with thanks!";
        $pp->delete;
    } else { 
        push @{$mm->{messages}}, "Something went wrong with your payment; we will be in touch with you to help resolve this.";
    }
    $mm->respond("plugins/invoice/view", invoice => $invoice);

}
sub _pay_invoice {
    my ($self, $invoice, $mm) = @_;
    my $paypal = Business::PayPal->new;
    my $base = Kirin->args->{base};
    if (!$base or !Kirin->args->{paypal_recipient}) { 
        Kirin::Utils->email_boss(
            severity => "critical",
            customer => $mm->{customer},
            context  => "trying to pay an invoice",
            message  => "Kirin is configured incorrectly - you must set the 'base' and 'paypal_recipient' parameters"
        );
        return;
    }
    my $button = $paypal->button(
      business => Kirin->args->{paypal_recipient},
      item_name => "Payment of invoice ".$invoice->id,
      return => "$base/paypal/return",
      cancel_return => "$base/paypal/cancel",
      amount => $invoice->total,
      currency_code => Kirin->args->{currency} || "GBP",
      quantity => 1,
      notify_url => "$base/paypal/ipn",
    );
    my $pp = Kirin::DB::Paypal->find_or_create({ invoice => $invoice });   
    $pp->magic_frob($paypal->id);
    $mm->{req}->env->{"plack.session"}->set("paypal_frob", $paypal->id);
    $pp->update();
    if (TESTING) { $button =~ s{www.paypal.com}{www.sandbox.paypal.com}g; }
    return $button;
}

sub _setup_db {
    Kirin::DB::Paypal->has_a(invoice => "Kirin::DB::Invoice");
}
1;
