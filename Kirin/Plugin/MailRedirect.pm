package Kirin::Plugin::MailRedirect;
use Email::Valid;
use strict;
use base 'Kirin::Plugin';
sub exposed_to     { 0 }
sub user_name      { "Mail Redirect" }
sub name           { "mail_redirect" }
sub default_action { "list" }
my $valid_check = Email::Valid->new(-mxcheck => 1);

Kirin::Plugin::MailRedirect->relates_to("Kirin::Plugin::Domain");

sub list {
    my ($self, $mm, $domain) = @_;
    my $r;
    ($domain, $r) = Kirin::DB::Domain->web_retrieve($mm, $domain);
    return $r if $r;

    my $dn = $domain->domainname;
    if ($mm->param("addpolicy")) {
        $self->_add_policy($mm, 
            domain => $domain,
            local  => $mm->param("local"),
            remote => $mm->param("remote"),
       );
        $self->_add_todo($mm, update => $domain->id);
    } elsif ($mm->param("deletepolicy")) {
        # Check email is part of this domain
        my $policy = Kirin::DB::MailRedirect->retrieve($mm->param("rid"));
        if ($policy and $policy->domain == $domain) {
            $policy->delete;
            $mm->message("Rule deleted");
            $self->_add_todo($mm, update => $domain->id);
        }
    }
    $mm->respond("plugins/mail_redirect/list", redirections => [ $domain->redirections ], 
        domain => $domain);
}

sub _add_policy {
    my ($self, $mm, %args) = @_;
    # Make sure it ends with our domain
    my $dn = $args{domain}->domainname;
    if ($args{local} !~ /\@$dn$/) { $args{local} .= "\@$dn"; }
    if (!$valid_check->address($args{local})) {
        $mm->message("Invalid local address"); return;
    }
    if (!$valid_check->address($args{remote})) {
        $mm->message("Invalid remote address"); return;
    } 
    Kirin::DB::MailRedirect->create({
        domain => $args{domain},
        local => $args{local},
        remote => $args{remote}
    });
}

sub _setup_db {
    shift->_ensure_table("mail_redirect");
    Kirin::DB::MailRedirect->has_a(domain => "Kirin::DB::Domain");
    Kirin::DB::Domain->has_many(redirections => "Kirin::DB::MailRedirect");
}

package Kirin::DB::MailRedirect;

sub sql {q{
CREATE TABLE IF NOT EXISTS mail_redirect (
    id integer primary key not null,
    domain integer,
    local varchar(255),
    remote varchar(255)
)
}};

1;

