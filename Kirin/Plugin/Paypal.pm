package Kirin::Plugin::Paypal;
use base 'Kirin::Plugin';
use Business::PayPal;

sub _skip_auth { "ipn" }

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
    return $button;
}
1;
