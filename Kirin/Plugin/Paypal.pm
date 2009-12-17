package Kirin::Plugin::Paypal;
use base 'Kirin::Plugin';
use constant TESTING => 1;
use Business::PayPal;

sub _skip_auth { "ipn" }

sub cancel { 
    my ($self, $mm) = @_;
    # Back to reviewing the invoice;
    my $frob = $mm->{req}->parameters->{custom};
    my ($pp) = Kirin::DB::Paypal->search(magic_frob => $frob);
    if (!$pp) { # Something's gone weird, return them to their customer page
        Kirin::Plugin::Customer->view($mm);
    }
    my $invoice = $pp->invoice;
    $pp->delete;
    push @{$mm->{messages}}, "You cancelled the invoice payment";
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
    $pp->update();
    if (TESTING) { $button =~ s{www.paypal.com}{www.sandbox.paypal.com}g; }
    return $button;
}

sub _setup_db {
    Kirin::DB::Paypal->has_a(invoice => "Kirin::DB::Invoice");
}
1;
