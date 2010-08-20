package Kirin::Plugin::Broadband;
use Time::Piece;
use Time::Seconds;
use Date::Holidays::EnglandWales;
use strict;
use base 'Kirin::Plugin';
use Net::DSLProvider;
sub user_name      { "Broadband" }
sub default_action { "view" }
use constant MAC_RE => qr/[A-Z0-9]{12,14}\/[A-Z]{2}[0-9]{2}[A-Z]/;
my $murphx;

sub order {
    my ($self, $mm) = @_;
    my $clid = $mm->param("clid");
    $clid =~ s/\D*//g;
    my $mac  = uc $mm->param("mac");
    my $stage = $mm->param("stage");
    goto "stage_$stage" if $stage;
    
    stage_1:
        if (!$clid) { 
            return $mm->respond("plugins/broadband/get-clid");
        }
        if (defined $mac and $mac !~ MAC_RE) {
            $mm->message("That MAC was not well-formed; please check.");
            return $mm->respond("plugins/broadband/get-clid");
        } 

        # XXX
        my %avail = $murphx->services_available(
            cli => $clid,
            defined $mac ? (mac => $mac) : ()
        );
        # Present list of available services, activation date.
        return $mm->respond("plugins/broadband/signup",
            services => \%avail);

    stage_2:
        # Decode service XXX
        my $provider = "Murphx"; # XXX;
        my $handle = Kirin::DB::Broadband->provider_handle($provider);
        return $mm->respond("plugins/broadband/terms-and-conditions",
            tandc => $handle->terms_and_conditions()
        );

    stage_3:
        if (!$mm->param("tc_accepted")) { # Back you go!
            $mm->param("Please accept the terms and conditions to complete your order"); 
            goto stage_2;
        }
        # make the order XXX
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

sub request_mac {
    my ($self, $mm) = @_;
    my ($bb, $r); (($bb, $r) = $self->_has_bb($mm))[0] or return $r;
    if ($bb->status !~ /^live/) { 
        $mm->message("You request a MAC for a service that is not live"); 
        return $self->view($mm);
    }

    my %out = eval {
        $bb->provider_handle->request_mac("service-id" => $bb->token,
            reason => "EU wishes to change ISP");
    };

    if ($@) { 
        $mm->message("An error occurred and your request could not be completed");
    }
    $mm->respond("plugins/broadband/mac-requested",
        mac_information => \%out # Template will sort out requested/got
    );
}

sub password_change {
    my ($self, $mm) = @_;
    my ($bb, $r); (($bb, $r) = $self->_has_bb($mm))[0] or return $r;
    
    my $pass = $mm->param("password1");
    if (!$pass) {
        $mm->message("Please enter your new password"); goto fail;
    }
    if ($pass ne $mm->param("password2")) {
        $mm->message("Passwords don't match"); goto fail;
    }
    if (!$self->_validate_password($mm, $pass)) { goto fail; }

    my $ok = $bb->provider_handle->change_password("service-id" => $bb->token,
        password => $pass);
    if ($ok) { 
        $mm->message("Password successfully changed: please remember to update your router settings!");
    } else { 
        $mm->message("Password WAS NOT changed");
    }
    return $self->view($mm);

    fail: return $mm->respond("plugins/broadband/password_change");
}

sub regrade {
    my ($self, $mm) = @_;
    my ($bb, $r); (($bb, $r) = $self->_has_bb($mm))[0] or return $r;
    my $new_product = $mm->param("newproduct"); # XXX
    my %out;
    if ($new_product) { 
        %out = eval {
            $bb->provider_handle->regrade("service-id" => $bb->token,
                                "prod-id" => $new_product);
        };
        if ($@) { 
            $mm->message("An error occurred and your request could not be completed");
        }
    }
    $mm->respond("plugins/broadband/regrade",
        information => \%out,
        service => $bb
    );
}

sub cancel { 
    my ($self, $mm) = @_;
    my ($bb, $r); (($bb, $r) = $self->_has_bb($mm))[0] or return $r;

    if (!$mm->param("date")) {
        $mm->message("Please choose a date for cancellation");
        return $mm->respond("plugins/broadband/cancel", 
            dates => $self->_dates
        )
    }

    return $mm->respond("plugins/broadband/confirm-cancel")
        if !$mm->param("confirm");
    
    my $out = eval {
        $bb->provider_handle->cease("service-id" => $bb->token,
            reason => "This service is no longer required",
            crd    => $mm->param("date")
        ); 
    };
    if ($@) { 
        $mm->message("An error occurred and your request could not be completed: $@");
        return $self->view($mm);
    }
    $bb->status("live-ceasing");

    Kirin::DB::BroadbandEvent->create({
        broadband   => $bb,
        timestamp   => Time::Piece->new(),
        class       => "cease",
        token       => $out,
        description => "Request to cease DSL provision"
    });
    $mm->message("Cease request sent to DSL provider");
    $self->view($mm);
}

sub _has_bb {
    my ($self, $mm) = @_;
    my $bb = $mm->{customer}->broadband;
    if (!$bb) { 
        $mm->message("You don't have any broadband services!");
        return (undef, $self->view($mm));
    }
    return $bb;
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
    Kirin::DB::Broadband->has_a(service => "Kirin::DB::BroadbandService");
    Kirin::DB::Customer->might_have(broadband => "Kirin::DB::Broadband");
    Kirin::DB::BroadbandEvent->has_a(broadband => "Kirin::DB::Broadband");
    Kirin::DB::Broadband->has_many(events => "Kirin::DB::BroadbandEvent");
    Kirin::DB::BroadbandUsage->has_a(broadband => "Kirin::DB::Broadband");
    Kirin::DB::Broadband->has_many(usage_reports => "Kirin::DB::BroadbandUsage");
    Kirin::DB::BroadbandEvent->has_a(event_date => 'Time::Piece',
      inflate => sub { Time::Piece->strptime(shift, "%Y-%m-%d") },
      deflate => 'ymd',
    );
}

sub _dates {
    my $start = Time::Piece->new() + ONE_WEEK;
    my $end = $start + ONE_MONTH;
    my @dates;
    while ( $start < $end ) {
        push @dates, $start->new($start) # Make a copy
            unless ($start->wday == 1 || $start->wday == 7) 
                    || is_holiday($start->ymd);
        $start += ONE_DAY;
    }
    return \@dates;
}

package Kirin::DB::Broadband;

sub provider_handle {
    my $self = shift;
    my $p = shift || $self->service->provider;
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
    service integer,
    token varchar(255),
    status varchar(255)
);

CREATE TABLE IF NOT EXISTS broadband_event (
    id integer primary key not null,
    broadband integer,
    event_date datetime,
    token varchar(255),
    class varchar(255),
    description text
);

CREATE TABLE IF NOT EXISTS broadband_usage (
    id integer primary key not null,
    broadband integer,
    year integer,
    month integer,
    input integer,
    output integer    
);

CREATE TABLE IF NOT EXISTS broadband_service (
    id integer primary key not null,
    provider varchar(255),
    name varchar(255),
    price decimal(5,2)
);
/}
1;
