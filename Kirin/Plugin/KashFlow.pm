package Kirin::Plugin::KashFlow;
use base 'Kirin::Plugin';
sub exposed_to { 0 }
use Net::KashFlow;

map {
    Kirin->args->{$_} 
        or die "You're using the Kashflow plugin but haven't defined $_!"
    } qw/ kashflow_username kashflow_password /;

my $kf = Net::KashFlow->new(username => Kirin->args->{kashflow_username},
                            password => Kirin->args->{kashflow_password});

sub _account_for_invoice {
    my ($self, $invoice) = @_;
    # Find or create the customer profile
    my $c;
    $c = $kf->get_customer($invoice->customer->billing_email);
    if(!$c) { 
        my $cust = $invoice->customer;
        $c = $kf->create_customer({
            Email => $cust->billing_email,
            Name => $cust->forename." ".$cust->surname,
            # ...
        });
        if (!$c) { die "Couldn't create customer in Kashflow" }
    }
    my $i = $kf->create_invoice({
        InvoiceNumber => $invoice->id,
        CustomerID => $c->CustomerID
    });
    for ($invoice->invoicelineitems) {
        $i->add_line({ 
            Quantity => 1, 
            Description => $_->description,
            Rate => $_->cost
        });
    }
    $i->pay({ PayAmount => $invoice->total });
}
   
__END__

#my $c = Net::Kashflow::Customer->new($kf,
#    Name => "Second Test",
#    Email => 'test2@netthink.co.uk',
#    PostCode => "GL2 0PX"
#);
#$c->insert;

$i = $i->add_line({
    Quantity => 4,
    Description => "Widgets",
    Rate => "17.50",
    VatRate => 15
}) or die "Couldn't add line";
$i->{Paid} = 1;
$i->update() or die "Couldn't pay invoice";

