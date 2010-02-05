package Kirin::Plugin::Broadband;
use strict;
use base 'Kirin::Plugin';
use Net::DSLProvider;
sub user_name      { "Broadband" }
sub default_action { "view" }
my $murphx;

sub order {
    my ($self, $mm) = @_;
    if (my $clid = $mm->param("clid")) {
        my %avail = $murphx->services_available($clid);
        return $mm->respond("plugins/broadband/signup",
            services => \%avail);
    }
}

sub view {
    my ($self, $mm) = @_;
    # Do we have a service? If so, say something about it.
    if (my $bb = $mm->{customer}->broadband) { 
        # Get current bandwidth usage info - force update, and history 
        # will be available to the template as broadband.usage_reports
        # You may wish to rely on a cached one instead, but for the
        # purposes...
        $bb->get_bandwidth_for(undef,undef); #,1);
        # Get any other status we care about
        # XXX How do I find out how much bandwidth allowance we have?

        return $mm->respond("plugins/broadband/currentstatus",
            broadband => $bb,
        );
    } else {
        return $mm->respond("plugins/broadband/get-clid");
    }
}

sub _handle_cancel_request {
    my ($self, $customer, $service) = @_;
    # If we're out of databases, get someone to (carefully) delete them
}

sub _setup_db {
    Kirin->args->{$_}
        || die "You need to configure $_ in your Kirin configuration"
        for qw/murphx_username murphx_password murphx_clientid/;
    use Net::DSLProvider::Murphx; # XXX
    $murphx = Net::DSLProvider::Murphx->new({
        user => Kirin->args->{murphx_username},
        pass => Kirin->args->{murphx_password},
        clientid => Kirin->args->{murphx_clientid}
    });

    shift->_ensure_table("broadband");
    Kirin::DB::Broadband->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Customer->might_have(broadband => "Kirin::DB::Broadband");
    Kirin::DB::BroadbandEvent->has_a(broadband => "Kirin::DB::Broadband");
    Kirin::DB::Broadband->has_many(events => "Kirin::DB::BroadbandEvent");
    Kirin::DB::BroadbandUsage->has_a(broadband => "Kirin::DB::Broadband");
    Kirin::DB::Broadband->has_many(usage_reports => "Kirin::DB::BroadbandUsage");
}

package Kirin::DB::Broadband;

sub provider_handle {
    my $self = shift;
    my $p = $self->provider;
    my $module = "Net::DSLProvider::".ucfirst($p);
    $module->require or die "Can't find a provider module for $p:$@";
    $module->new({ 
        user     => Kirin->args->{"${p}_username"},
        pass     => Kirin->args->{"${p}_password"},
        clientid => Kirin->args->{"${p}_clientid"},
    });
}

sub get_bandwidth_for {
    my ($self, $year, $mon, $replace) = @_;
    $year ||= 1900 + (localtime)[5];
    $mon  ||= 1    + (localtime)[4];
    $mon = sprintf("%02d", $mon);
    my ($bw) = $self->usage_reports(year => $year, month => $mon);
    if ($bw and !$replace) {
        return ($bw->input, $bw->output);
    }
    my %summary = $self->provider_handle->usage_summary(
        "service-id" => $self->token,
        year => $year,
        month => $mon
    );
    if ($bw) { 
        $bw->input($summary{"total-input-octets"});
        $bw->output($summary{"total-output-octets"});
    } else {
        $self->add_to_usage_reports({
            year => $year,
            month => $mon,
            input => $summary{"total-input-octets"},
            output => $summary{"total-output-octets"},
        });
    }
    return ($summary{"total-input-octets"}, $summary{"total-output-octets"});
}

sub sql {q/
CREATE TABLE IF NOT EXISTS broadband (
    id integer primary key not null,
    customer integer,
    telno varchar(12),
    provider varchar(255),
    token varchar(255),
    status varchar(255)
);

CREATE TABLE IF NOT EXISTS broadband_event (
    id integer primary key not null,
    broadband integer
);

CREATE TABLE IF NOT EXISTS broadband_usage (
    id integer primary key not null,
    broadband integer,
    year integer,
    month integer,
    input integer,
    output integer    
);
/}
1;
