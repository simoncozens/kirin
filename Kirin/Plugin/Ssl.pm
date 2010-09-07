package Kirin::Plugin::Ssl;
use base 'Kirin::Plugin';
sub user_name      { "SSL Certificates" }
sub default_action { "list" }
our $debug;
our $enom;
use Net::eNom;
use strict;
use warnings;

use Carp qw/croak/;
use Socket qw/inet_ntoa/;
use Sys::Hostname;
use JSON;

my $json = JSON->new->allow_blessed;

sub list {
    my ($self, $mm) = @_;
    my @certificates = $mm->{customer}->ssls;

    my @orders = Kirin::DB::Orders->search(order_type => 'SSL Certificate',
        customer => $mm->{customer});

    $mm->respond("plugins/ssl/list", certificates => \@certificates,
        orders => \@orders, addable => 1 );
}

sub order {
    my ($self, $mm) = @_;

    if (!$mm->param("ordering")) {
        my %args = ( products => [Kirin::DB::SslProducts->retrieve_all] );
        return $mm->respond("plugins/ssl/orderform", %args); 
    }

    # Load up request from the parameters, checking as we go
    my $ok      = 1;
    my $request = {};
    my $params  = $mm->{req}->parameters;

    # Don't forget that purchase_ssl_cert actually does a bit of
    # checking too, we'll use that.
    my %need = map { $_ => 1 } qw/AdminFName AdminLName AdminAddress1
        AdminCity AdminCountry AdminPostalCode AdminPhone AdminEmailAddress
        ProductType /;
    my $sendthemback = sub {
        $mm->message(shift);
        $mm->respond("plugins/ssl/orderform", products => [Kirin::DB::SslProducts->retrieve_all],
            oldparams => $mm->{req}->parameters);
    };
    my $domain = delete $params->{Domain} ||
        return $sendthemback->("Need to specify a domain name");
    my $orgname = delete $params->{OrgName} ||
        return $sendthemback->("Need to specify an organisation name");
    my $country = delete $params->{CountryCode} ||
        return $sendthemback->("Need to specify a country code");
    my $x509 = delete $params->{X509} || "/C=$country/O=$orgname/CN=$domain";

    for (keys %$params) {
        delete $need{$_};
        if (/^(Admin|Billing|Tech)(.*)$/) { 
            $request->{$1}{$2} = $params->{$_} if $params->{$_}; 
        }
        else { $request->{$_} = $params->{$_} } 
    }
    if (keys %need) {
        return $sendthemback->("You need to fill in these fields: " . join ", ", keys %need);
    }
    my ($key, $csr) = _make_key_csr($x509);
    warn Dumper($request) if $debug;
    $request->{CSR} = $csr;

    my $order = undef;
    if ( ! $params->{order} || ! ( $order = Kirin::DB::Orders->retrieve($params->{order}) ) ) {
        my @product = Kirin::DB::SslProducts->search( name => $params->{ProductType} );
        return $sendthemback->("Invalid SSL Product") unless $product[0];
        my $invoice = $mm->{customer}->bill_for( {
            description     => "SSL Certificate for $domain",
            cost            => $product[0]->price
        } );

        $order = Kirin::DB::Orders->insert( {
            customer    => $mm->{customer},
            order_type  => 'SSL Certificate',
            module       => __PACKAGE__,
            parameters  => $json->encode( {
                customer     => $mm->{customer},
                domain       => $domain,
                csr          => $csr,
                key_file     => $key,
                request      => $request
            }),
            invoice     => $invoice->id,
        });
        $order->set_status("New Order");

        $order->set_status("Invoiced");
        $mm->{order} = $order->id;
    }
    else {
        $order = Kirin::DB::Orders->retrieve($params->{order});
    }

    if ( $order->status eq 'Invoiced' ) {
        return $mm->respond("plugins/invoice/view", invoice => $order->invoice);
    }

    $self->view($mm, $order->id);
}

sub view {
    my ($self, $mm, $id) = @_;

    $self->list($mm) if ! $id;

    my $order = Kirin::DB::Orders->retrieve($id);
    $self->list($mm) if ! $order;

    my $order_details = $json->decode($order->parameters);
    my $cert = Kirin::DB::SslCertificate->retrieve($order_details->{certid});

    if ( $order->status eq 'Pending - with suppiler') {
        $cert->update_from_enom;
    }

    return $mm->respond("plugins/ssl/view", cert => $cert);
}

sub process {
    my ($self, $id) = @_;
    if ( ! $id ) { return; }

    my $order = Kirin::DB::Orders->retrieve($id);
    if ( ! $order || ! $order->invoice->paid ) { return; }

    if ( $order->module ne __PACKAGE__ ) { return; }

    my $op = $json->decode($order->parameters);

    my ($certid, $status) = eval { _purchase_ssl_cert($enom, $op->{request}) };
    if (!$certid) {
        Kirin::Utils->email_boss(
            severity    => "error",
            customer    => $op->{customer},
            context     => "Trying to purchase SSL Certificate " . $op->{certid},
            message     => "$@"
        );
        return;
    }

    my $cert = Kirin::DB::SslCertificate->create({
        customer     => $op->{customer},
        domain       => $op->{domain},
        enom_cert_id => $op->{certid},
        csr          => $op->{csr},
        key_file     => $op->{key},
    });

    $order->parameters($json->encode( { certid => $cert->id } ));
    $order->update;

    $order->set_status('Pending - with suppiler');

    return 1;
}

sub download {
    my ($self, $mm, $certid, $part) = @_;
    my $cert = Kirin::DB::SslCertificate->retrieve($certid);
    if (!$cert) {
        $mm->message("That certificate doesn't exist!");
        return $self->list($mm);
    } elsif ($cert->customer != $mm->{customer}) {
        $mm->message("That certificate isn't yours!");
        return $self->list($mm);
    } elsif ($part !~ /^(csr|key_file|certificate)$/) {
        return $self->list($mm);
    }
    my $response = Plack::Response->new(200);
    $response->body($cert->$part);
    $response->content_type('text/plain');
    return $response;
}

sub _setup_db {   # Piggyback on this method as it's called when ->args is ready
    my $db = shift;
    Kirin->args->{$_}
        || die "You need to configure $_ in your Kirin configuration"
        for qw/enom_reseller_username enom_reseller_password/;
    $enom = Net::eNom->new(
        username => Kirin->args->{enom_reseller_username},
        password => Kirin->args->{enom_reseller_password},
        test     => 1);                                      # XXX
    $db->_ensure_table("ssl_certificate");
    $db->_ensure_table("ssl_products");
    Kirin::DB::SslCertificate->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->has_many(ssls => "Kirin::DB::SslCertificate");
}

#my ($key, $csr) = make_key_csr("/C=US/O=Disney Corporation/CN=disney.com");
#purchase_ssl_cert($enom, {
#        ProductType => "Certificate-GeoTrust-QuickSSL",
#        CSR         => $csr,
#        Admin       => {
#            FName            => "Michael",
#            LName            => "Mouse",
#            Address1         => "P.O. Box 10000",
#            City             => "Lake Buena Vista",
#            State            => "FL",
#            PostalCode       => "32830",
#            Country          => "US",
#            Phone            => "+1.4079396244",
#            EmailAddress     => 'mickey@disney.com'
#            }
#});

# Creates a private key and CSR for a given X509 property string. Example:
# ($key, $csr) = _make_key_csr("/C=GB/O=UK Free Software Network/CN=ukfsn.org");
# $csr will be raw Base64 digits, key will be headered text file;
sub _make_key_csr {
    use File::Temp qw/tempdir/;
    use File::Slurp;
    my $x509 = shift;
    my $dir = tempdir(CLEANUP => 1);
    system("openssl genrsa -out $dir/domain.key 2048 2>/dev/null");
    system("openssl req -new -key $dir/domain.key -out $dir/domain.csr -subj '$x509'");
    my $key = read_file("$dir/domain.key");
    my $csr = read_file("$dir/domain.csr");
    $csr =~ s/-----(BEGIN|END) CERTIFICATE REQUEST-----//g;
    $csr =~ s/\s//gms;
    return ($key, $csr);
}

# Purchase a certificate from enom; returns certid if successful,
# (undef, $where) otherwise, where $where tells you what stage the
# request got to.

sub _purchase_ssl_cert {
    my $enom = shift;
    my %args = %{+shift};
    my $ip   = inet_ntoa(scalar gethostbyname(hostname() || 'localhost'));

    croak "You need to pass a certificate signing request\n"
        unless exists $args{CSR};
    croak "You need to pass a valid ProductType\n"
        unless exists $args{ProductType};
    $args{Tech} ||= $args{Billing} ||= $args{Admin} ||
        croak "You have to pass at least an admin user\n";
    my @fields = qw/FName LName Address1 City
        PostalCode Country Phone EmailAddress/;

    my %contactargs;
    for my $type (qw/Tech Billing Admin/) {
        $args{$type}{$_} ||
            croak "Required parameter \$args{$type}{$_} not supplied\n"
            for @fields;
        $args{$type}{Phone} =~ /\+\d+\.\d+/
            or croak "Phone number for $_ contact must be in format +CountryCode.PhoneNumber\n";
        $args{$type}{Province} || $args{$type}{State} ||
            croak "Required parameter \$args{$type}{Province/State} not supplied\n";
        $contactargs{$type . $_} = $args{$type}{$_} for keys %{$args{$type}};
    }

    my $cart = $enom->AddToCart(
        EndUserIP   => $ip,
        ProductType => $args{ProductType},
        Quantity    => $args{NumYears} || 1,
        ClearItems  => 1
    );
    warn Dumper($cart) if $debug;
    my $insert = $enom->InsertNewOrder(EndUserIP => $ip);
    warn Dumper($insert) if $debug;
    my $orderid = $insert->{OrderID};
    if ($insert->{errors}) { return (undef, join ". ", @{$insert->{errors}}); }
    return (undef, "No order id") unless $orderid;

   # CertGetCerts Retrieve the ID number for this cert, to use in configuring it
    my $thiscert;
    my $attempts = 4;
    while (!$thiscert && $attempts) {
        warn "Trying to get certificate again\n" if $debug;
        my @certs = @{$enom->CertGetCerts->{CertGetCerts}{Certs}{Cert}};
        ($thiscert) = grep { defined $_->{OrderID} && $_->{OrderID} == $orderid } @certs;
        if (!$thiscert) {
            warn "Can't get the certificate we just ordered, $attempts left...";
            sleep 15;
            $attempts--
        }
    }
    return (undef, "Couldn't find the certificate we just ordered")
        unless $thiscert;

   #    CertConfigureCert Obtain information from customer to configure the cert
    warn "Configuring cert" if $debug;
    my $config = $enom->CertConfigureCert(
        CertID        => $thiscert->{CertID},
        WebServerType => 1,
        CSR           => $args{CSR},
        %contactargs
    );
    if ($config->{errors}) { return (undef, join ". ", @{$config->{errors}}); }
    my $approver = $config->{CertConfigureCert}{Approver}[0]{ApproverEmail};
    return (undef, "Couldn't configure cert") unless $approver;

    warn "Purchasing cert" if $debug;
    $enom->CertPurchaseCert(
        CertID        => $thiscert->{CertID},
        ApproverEmail => $approver
    );
    return $thiscert->{CertID};
}

sub admin {
    my ($self, $mm) = @_;
    if (!$mm->{user}->is_root) { return $mm->respond("403handler") }

    my $id = undef;

    if ($mm->param("create")) {
        if ( ! $mm->param('name') ) {
            $mm->message("You must specify the product name");
        }
        elsif ( ! $mm->param('supplier') ) {
            $mm->message("You must specify the supplier");
        }
        elsif ( ! $mm->param('periods') ) {
            $mm->message("You must specify the valid periods in months");
        }
        elsif ( ! $mm->param('price') ) {
            $mm->message("You must specify the price");
        }
        else {
            my $product = Kirin::DB::SslProducts->create({
                map { $_ => $mm->param($_) } 
                    qw/name supplier periods price/
            });
            $mm->message("SSL Product created") if $product;
        }
    }
    elsif ( $id = $mm->param('editproduct') ) {
        my $product = Kirin::DB::SslProducts->retrieve($id);
        if ( $product ) {
            for (qw/name supplier periods price/) {
                $product->$_($mm->param($_));
            }
            $product->update();
        }
    }
    elsif ( $id = $mm->param('deleteproduct') ) {
        my $product = Kirin::DB::SslProducts->retrieve($id);
        if ( $product ) { $product->delete; $mm->message("SSL Product deleted"); }
    }
    my @products = Kirin::DB::SslProducts->retrieve_all();
    $mm->respond('plugins/ssl/admin', products => \@products);
}

package Kirin::DB::SslCertificate;

sub update_from_enom {
    my $self = shift;
    my $r = $enom->CertGetCertDetail(CertID => $self->enom_cert_id);
    return unless $r->{CertGetCertDetail};
    $self->cert_status($r->{CertGetCertDetail}{CertStatus});
    $self->csr($r->{CertGetCertDetail}{CSR});
    if (!$self->certificate) {
        $self->certificate($r->{CertGetCertDetail}{SSLCertificate});
    }
    $self->update;
}

package Kirin::DB::Ssl; # Just for deployment

sub sql {q|
CREATE TABLE IF NOT EXISTS ssl_certificate ( id integer primary key not null,
    customer integer,
    enom_cert_id integer,
    domain varchar(255), /* We could parse the CSR but that's horrid */
    csr text,
    key_file text,
    certificate text,
    cert_status varchar(255)
);

CREATE TABLE IF NOT EXISTS ssl_products (id integer primary key not null,
    name varchar(255) not null,
    price varchar(255) not null,
    supplier integer not null,
    periods varchar(255) not null
);
|}
1;
