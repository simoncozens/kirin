package Kirin::Utils;
use warnings;
use strict;
use Data::Dumper;
use Email::Send;

sub email_boss {
    my ($self, %args) = @_;
    my $boss = Kirin::DB::User->retrieve(1)->customer;
    # We don't use a template here because we might be emailing because
    # the template failed...
    my $email = <<EOF;
From: Kirin Domain Management System <kirin\@localhost>
To: @{[$boss->forename. " ". $boss->surname. " <". $boss->email.">"]} 
Subject: [$args{severity}] Notification from Kirin

While Kirin was $args{context} the following event occured:

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

sub templated_email {
    my ($self, %args) = @_;
    my $boss = Kirin::DB::User->retrieve(1)->customer;
    my $t = Template->new({
        INCLUDE_PATH => (Kirin->args->{templates} || "templates")
    });
    my $mail;
    if ($t->process("mail/$args{template}", {
        boss => $boss,
        %args,  
        }, \$mail)) {
        Kirin::Utils->send_email($mail);
    } else {
        Kirin::Utils->email_boss(
            severity => "error",
            context  => "trying to send an email",
            message  => $t->error."\n\nParameters were: ".Dumper(\%args)
        );
    }
}

sub gen_pass {
    my ($self, @data) = @_;
    my $pw;
    my $checker = Data::Password::BasicCheck->new(5,20,0);
    my @bits = ("a".."z", "A".."Z", 0..9, split //, ",./<>?;'[]{}\@");
    do {
        $pw = "";
        for (1..8+(rand(5))) { $pw .= $bits[rand @bits] }
    } while $checker->check($pw, @data) =~ /^([1346]|127)$/;
    return $pw;
}
1;

