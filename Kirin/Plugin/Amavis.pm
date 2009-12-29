package Kirin::Plugin::Amavis;
use Email::Valid;
use strict;
use base 'Kirin::Plugin';
sub exposed_to     { 0 }
sub user_name      { "Mail Filtering Rules" }
sub default_action { "list" }

my %default_policy = (
    virus_lover => "Y", spam_lover => "Y", spam_modifies_subj => "N",
    bypass_virus_checks => "Y", bypass_spam_checks => "Y",
    spam_tag_level => 999, spam_tag2_level => 999,
    spam_kill_level => 999
);

sub list {
    my ($self, $mm, $domain) = @_;
    $domain = Kirin::DB::Domain->retrieve($domain);
    if (!$domain) {
        $mm->message("You need to select a domain first");
        return Kirin::Plugin::Domain->list($mm);
    }
    if ($domain->customer != $mm->{customer}) {
        $mm->message("That's not your domain!");
        return Kirin::Plugin::Domain->list($mm);
    }
    if ($mm->param("editing")) { # Adding and editing are the same
        my $localpart = $mm->param("localpart");
        my $email     =  $localpart . '@' . $domain->domainname;
        if (!Email::Valid->address($email)) {
            $mm->message("That's not a valid email address");
            return Kirin::Plugin::Domain->list($mm);
        }

        my %policy = %default_policy;
        $policy{virus_lover} = 'N', $policy{bypass_virus_checks} = 'N'
            if $mm->param('filtervirus');
        $policy{spam_lover} = 'N', $policy{bypass_spam_checks} = 'N'
            if $mm->param('filterspam');
        $policy{spam_modifies_subj} = 'Y' if $mm->param('modifysubject');
        $policy{spam_tag_level} = $mm->param('taglevel') if $mm->param('taglevel');
        $policy{spam_tag2_level} = $mm->param('tag2level') if $mm->param('tag2level');
        $policy{spam_kill_level} = $mm->param('killlevel') if $mm->param('killlevel');

        my $policy = Kirin::ExternalDB::Amavis::Policy->find_or_create({
            policy_name => $email
        });
        $policy->$_($policy{$_}) for keys %policy;
        $policy->update();

        # Now tie that policy to the email address
        my $entry = Kirin::ExternalDB::Amavis::Users->find_or_create({
            email => $email
        });
        $entry->policy_id($policy->id);
        $entry->update();

        $mm->message("Rule added");
    }
    my @rules = Kirin::ExternalDB::Amavis::Policy->search_like(
            policy_name => "%\@".$domain->domainname
    );
    $mm->respond("plugins/amavis/list", rules => \@rules, domain => $domain);
}

sub _setup_db {
    my $dsn = Kirin->args->{amavis_dsn} 
        or die "You need to set the amavis_dsn configuration argument to use the amavis plugin";
    my $loader = Class::DBI::Loader->new(
        dsn => $dsn,
        user => Kirin->args->{amavis_db_user},
        password => Kirin->args->{amavis_db_password},
        namespace => "Kirin::ExternalDB::Amavis",
        options => { AutoCommit => 1 },
        relationships => 1,
    );

    
}

1;

