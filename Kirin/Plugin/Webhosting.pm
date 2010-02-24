package Kirin::Plugin::Webhosting;
use strict;
use base 'Kirin::Plugin';
sub exposed_to     { 0 }
sub user_name      { "Web Hosting" }
sub default_action { "list" }
use Regexp::Common qw/net dns/;

Kirin::Plugin::Webhosting->relates_to("Kirin::Plugin::Domain");

sub list {
    my ($self, $mm, $domain) = @_;
    my $r;
    ($domain, $r) = Kirin::DB::Domain->web_retrieve($mm, $domain);
    return $r if $r;

    my $hosting;
    my %features = $self->_available_features($mm);
    if ($mm->param("hid")) { 
        $hosting = Kirin::DB::Webhosting->retrieve($mm->param("hid"));
        if (!$hosting or $hosting->domain->customer != $mm->{customer}) {
            $mm->message("That's not your hosting!"); goto done;
        }
    }

    if ($mm->param("deletehosting") and $hosting) { 
        $self->_add_todo($mm, delete => $hosting->hostname, $domain->domainname);
        $hosting->delete;
        goto done;
    }
    if ($mm->param("addhosting")) {
        # Can I add one? (Check quota)
        # Is this in my domain?!
        # Hostname characters OK?
        my $hostname = join ".", $mm->param("hostname"), $domain->domainname;
        if ($hostname =~ /^$RE{dns}{data}{cname}$/) {
            $hosting = Kirin::DB::Webhosting->create({
                domain => $domain, hostname => $hostname });
            $self->_add_todo($mm, create => $hosting->id);
            $mm->message("Your site has been configured and will be available shortly");
        } else {
            $mm->message("Hostname contains illegal characters");
        }
    }
    # If we're still here, we're either editing or adding, so edit feature set
    $self->_edit_featureset($mm, $hosting, \%features) if $hosting;

    done:
    $mm->respond("plugins/webhosting/list", domain => $domain,
        available_features => [ keys %features ], 
        hostings => [ $domain->webhostings ]
    );
}

sub _edit_featureset {
    my ($self, $mm, $hosting, $features) = @_;
    # Remove feature / add feature
    if (my $f = $mm->param("addfeature")) { 
        if ($features->{$f} < 1 and $features->{$f} != -1) {
            # It won't be displayed in the interface but they may be evil
            $mm->message("Your account does not allow you to add $f to your web hosting.");
        } else {  
            my $path = $mm->param("path");
            # XXX Check path
            my $fobj = Kirin::DB::WebhostingFeature->create({
                hosting => $hosting, feature => $f, path => $path
            });
            $mm->message("Feature added");
            $self->_add_todo($mm, add_feature => 
                join ":", $hosting->id, $fobj->feature, $fobj->path);
        } 
    }
    if (my $f = $mm->param("rmfeature")) {
        my ($fobj) = Kirin::DB::WebhostingFeature->retrieve($f);
        return unless $fobj;
        if ($fobj->hosting != $hosting) {
            $mm->message("That's not yours to remove!");
        }
        $features->{$fobj->feature}++ unless $features->{$fobj->feature} = -1;
        $self->_add_todo($mm, remove_feature => 
                join ":", $hosting->id, $fobj->feature, $fobj->path);
        $fobj->delete;
        $mm->message("Feature removed");
    }
}

sub _available_features {
    my ($self, $mm) = @_;
    my %features;
    # Get the quota of 
    for (map {$_->parameter}
        grep { $_->plugin eq $self->name and $_->parameter !~ /^(\d+|-1)$/}
        map { $_->package->services }
        $mm->{customer}->subscriptions
    ) {
        if (/(^\w+):(\d+|-1)/) { 
            $features{$1} = $2 == -1 ? -1 : $features{$1} + $2;
        } else { 
            $features{$_}++ 
        }
    }
    # De-quota the ones we've used
    for ( map { $_->features } map { $_->webhostings }
        $mm->{customer}->domains) {
        $features{$_->feature}-- unless $features{$_->feature} == -1;
    }
    return %features;
}

sub _setup_db {
    shift->_ensure_table("webhosting");
    Kirin::DB::Webhosting->has_a(domain => "Kirin::DB::Domain");
    Kirin::DB::Domain->has_many(webhostings => "Kirin::DB::Webhosting");
    Kirin::DB::WebhostingFeature->has_a(hosting => "Kirin::DB::Webhosting");
    Kirin::DB::Webhosting->has_many(features => "Kirin::DB::WebhostingFeature");
}

package Kirin::DB::Webhosting;

sub sql { q/
CREATE TABLE IF NOT EXISTS webhosting (
    id integer primary key not null,
    domain integer,
    hostname varchar(255)
);

CREATE TABLE IF NOT EXISTS webhosting_feature (
    id integer primary key not null,
    hosting integer,
    feature varchar(255),
    path varchar(1024)
);
/

}

1;

