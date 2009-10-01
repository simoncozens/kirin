package Kirin::Plugin::MailAlias;

sub name      { "mail_alias"            }
sub user_name { "Mail Aliases"          } 
sub target    { "Kirin::Plugin::Domain" }

sub handle {
    my ($self, $req, @args) = @_;
}

1;
