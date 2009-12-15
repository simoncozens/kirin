package Kirin::Utils;
use Email::Send;

sub email_boss {
    my ($self, %args) = @_;
    my $boss = Kirin::DB::User->retrieve(1)->customer;
    # We don't use a template here because we might be emailing because
    # the template failed...
    my $email = <<EOF;
From: Kirin Domain Management System <kirin\@localhost>
To: @{[$boss->forename, " ", $boss->surname, " <", $boss->email,">"]} 
Subject: [$args{severity}] Problem with Kirin

While Kirin was $args{context} an error occured:

$args{message}

EOF
    if ($args{customer}) {
        $email .= "Customer ".$args{customer}->id;
        $email .= " (".$args{customer}->forename." ".$args{customer}->surname.") ";
        $email .= "was affected by this error.";
    }
    $self->send_email($email);
}

sub send_email {
    my ($self, $email) = @_;
    my $sender = Email::Send->new({mailer => 'SMTP'});
    $sender->mailer_args([Host => Kirin->args->{smtp_server} || "localhost"]);
    $sender->send($email);
}

1;

