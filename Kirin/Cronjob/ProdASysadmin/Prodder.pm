package Kirin::Cronjob::ProdASysadmin::Prodder;
sub prod {
    my ($self, $job, $message) = @_;
    Kirin::Utils->email_boss(
        customer => $job->customer,
        severity => "action required",
        context  => "checking its cronjobs",
        message  => $message
    );
    return 1;
}

1;
