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

sub list {
    my ($self, $mm) = @_;
    my @certificates = $mm->{customer}->ssls;
    $mm->respond("plugins/ssl/list", certificates => \@certificates,
        addable => $self->_can_add_more($mm->{customer}));
}

sub order {
    my ($self, $mm) = @_;
    if (!$self->_can_add_more($mm->{customer})) {
        $mm->no_more("SSL certificates");
        return $self->list($mm);
    }

    if (!$mm->param("ordering")) { return $mm->respond("plugins/ssl/orderform"); }

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
        $mm->respond("plugins/ssl/orderform",
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
    use Data::Dumper; warn Dumper($request);
    $request->{CSR} = $csr;
    my ($certid, $status) = eval { _purchase_ssl_cert($enom, $request) };
    if (!$certid) {
        $mm->message("Something went wrong during processing: $status");
        if ($@) { $mm->message($@) }
        return $mm->respond("plugins/ssl/orderform",
            oldparams => $mm->{req}->parameters);
    }
    $self->list($mm);
    $mm->message("Order was successful");
    my $cert = Kirin::DB::SslCertificate->create({
        customer     => $mm->{customer},
        domain       => $domain,
        enom_cert_id => $certid,
        csr          => $csr,
        key_file     => $key,
    });
    $cert->update_from_enom;
    $self->list($mm);
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
    Kirin->args->{$_}
        || die "You need to configure $_ in your Kirin configuration"
        for qw/enom_reseller_username enom_reseller_password/;
    $enom = Net::eNom->new(
        username => Kirin->args->{enom_reseller_username},
        password => Kirin->args->{enom_reseller_password},
        test     => 1);                                      # XXX
    shift->_ensure_table("ssl_certificate");
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
        Quantity    => 1,
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
|}
1;
