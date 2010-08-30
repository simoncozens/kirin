package Kirin::Plugin::Orders;
use strict;
use base 'Kirin::Plugin';
sub user_name      { "Orders" }
sub default_action { "list" }

sub list {
    my ($self, $mm, $action) = @_;

    my $o_id = undef;
    if ( $o_id = $mm->param("cancel") && Kirin::DB::Orders->retrieve($mm->param("cancel")) ) {
        warn "Cancelling order $o_id";
        $self->delete($mm, $o_id);
    }

    # XXX Pager?
    my @orders = $mm->{user}->is_root ? Kirin::DB::Orders->retrieve_all()
                                      : $mm->{customer}->orders;

    $mm->respond("plugins/orders/list", orders => \@orders);
}

sub view {
    my ($self, $mm, $id) = @_;
    my $order = undef;
    if (!$id or !($order = Kirin::DB::Orders->retrieve($id))) {
        return $self->list($mm);
    }

    my @updates = Kirin::DB::OrderUpdates->search( orders => $id );
    $mm->respond("plugins/orders/view", order => $order);
}

sub delete {
    my ($self, $mm, $id) = @_;
    my $order;
    if (!$id or !($order = Kirin::DB::Orders->retrieve($id))) {
        return $self->list($mm);
    }
    if ($order->customer->id != $mm->{customer}->id and !$mm->{user}->is_root) {
        $mm->message("You can't delete that order, it's not yours!");
        return $self->list($mm);
    }
    if ( $order->{status} eq 'Completed' ) {
        $mm->message("You cannot delete that order. It has already completed");
        return $self->list($mm);
    }
    if ( $order->{status} eq 'Pending - with suppiler' ) {
        $mm->message("You cannot delete that order. It has already been processed to our supplier");
        return $self->list($mm);
    }

    # XXX delete the order and associated invoices/services

    my $i = Kirin::DB::Invoice->retrieve($order->invoice);
    if ( $i->paid ) {
        # XXX How to handle cancellation where invoice has been paid?
    }
    else {
        # If the invoice has not been paid we can safely cancel the order
        # as it wont have been processed.
        warn "Cannot cancel Invoice ". $order->invoice if ! $i->cancel();
        warn "Cannot delete order $id" if ! $order->delete;
    }
    return 1;
}

sub completed {
    my ($self, $id) = @_;
    return if ! $id;
    my $order = Kirin::DB::Orders->retrieve($id);
    $order->completed();
    return 1;
}

sub _setup_db {
    my $db = shift;
    $db->_ensure_table("orders");
    $db->_ensure_table("order_updates");
    Kirin::DB::Orders->has_a(customer => "Kirin::DB::Customer");
    Kirin::DB::Orders->has_a(invoice => "Kirin::DB::Invoice");
    Kirin::DB::Orders->has_many(orderupdates => "Kirin::DB::OrderUpdates");
    Kirin::DB::OrderUpdates->has_a(orders => "Kirin::DB::Orders");
    Kirin::DB::Customer->has_many(orders => "Kirin::DB::Orders");
    Kirin::DB::Invoice->has_many(orders => "Kirin::DB::Orders");
}

package Kirin::DB::Orders;

sub set_status {
    my ($self, $status) = @_;

    my $t = Time::Piece->new();

    Kirin::DB::OrderUpdates->insert( {
        orders => $self->id,
        datetime => $t->epoch,
        order_update => $status
    } );

    $self->status($status);
    $self->update;
}

sub completed {
    my $self = shift;
    $self->set_status("Completed");
}

sub sql {q/
CREATE TABLE IF NOT EXISTS orders (
    id integer primary key not null,
    customer integer,
    invoice integer,
    order_type varchar(255),
    module varchar(255),
    parameters text,
    status varchar(255)
);

CREATE TABLE IF NOT EXISTS order_updates (
    id integer primary key not null,
    orders integer,
    datetime datetime,
    order_update varchar(255)
);    
/}
1;
