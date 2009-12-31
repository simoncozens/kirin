package Regexp::Common::dns;
#
# $Id: dns.pm,v 1.10 2003/11/19 02:43:46 ctriv Exp $
#

use strict;
use vars qw($VERSION);

$VERSION = '0.00_01';

use Regexp::Common qw/pattern net/;

our $DEFAULT_RFC = 'hybrid';

=head1 NAME

Regexp::Common::dns - Common DNS Regular Expressions 

=head1 SYNOPSIS

 use Regexp::Common qw/dns/;
  
 while (<>) {
     $RE{'dns'}{'data'}{'mx'}  and print 'an mx';
     $RE{'dns'}{'data'}{'soa'} and print 'a soa';
 }

 if ($host =~ $RE{'dns'}{'domain'}) {
     print "hostname found';
 }

=head1 PATTERNS

=head2 $RE{'dns'}{'int16'}

Matches a 16 bit unsigned integer in base 10 format.

=cut

# 16 bit unsigned int is 65535
pattern name   => [qw(dns int16)],
		create => '(?k:6553[0-5]|655[0-2]\d|65[0-4]\d\d|6[0-4]\d{1,3}|[0-5]?\d{1,4})'
		;



=head2 $RE{'dns'}{'int32'}

Matches a 32 bit integer in base 10 format.

=cut
		
# 32 bit unsigned int is 4294967295
pattern name   => [qw(dns int32)],
		create => '(?k:429496729[0-5]|42949672[0-8]\d|4294967[0-1]\d\d|429496[0-6]\d{1,3}|42949[0-5]\d{1,4}|4294[0-8]\d{1,5}|429[0-3]\d{1,6}|42[0-8]\d{1,7}|4[0-1]\d{1,8}|[0-3]?\d{1,9})'
		;

=head2 $RE{'dns'}{'domain'}

Matches a DNS domain name.

By default this regexp uses a pragmatic combination of rfc1035, and
rfc2181.  This is intended to be in sprit with current DNS operation
practices.  This hybrid approach is simlar to rfc1035, but allows for
underscores, and for underscores and hyphens to begin or end a lable.
It also allows for wilcarding.  

The default rule can be set with the C<$Regexp::Common::dns::DEFAULT_RFC> 
global, which is not exported by this package.  
 
  
By default this regexp matches a domain name according to the rules of 
L<rfc1035|http://www.ietf.org/rfc/rfc1035.txt> section 2.3.1:

 <domain>      ::= <subdomain> | " "
 
 <subdomain>   ::= <label> | <subdomain> "." <label>
 
 <label>       ::= <letter> [ [ <ldh-str> ] <let-dig> ]
 
 <ldh-str>     ::= <let-dig-hyp> | <let-dig-hyp> <ldh-str>

 <let-dig-hyp> ::= <let-dig> | "-"

 <let-dig>     ::= <letter> | <digit>

 <letter>      ::= <[A-Za-z]>

 <digit>       ::= <[0-9]>

Labels must be 63 characters or less.

Domain names must be 255 octets or less.

RFC 1035 does not allow for wildcarding (C<*.example.com>).  If you want to 
match a wildcarded domain name, use the C<-wildcard> flag:

 $Regexp::Common::dns::DEFAULT_RFC = '1035'

 '*.example.com' =~ $RE{'dns'}{'domain'}{-wildcard};  # match
 '*.example.com' =~ $RE{'dns'}{'domain'};             # no match
 

RFC 1035 has been superseded by L<rfc2181|http://www.rfc-editor.org/rfc/rfc2181.txt> 
section 11:

=over 2

=item *

Labels can be any character except a C<.>.

=item *

Each label is no shorter than one octet.

=item *

Each lable is no longer than 63 octets.

=item *

A complete domain name may be no longer than 255 octets, including the separators. 

=back

For example:

 '_fancy.spf.record=4.org' =~ $RE{'dns'}{'domain'}{-rfc => 2181};

This regular expression does not match a single C<.>.
 
The minimum number of lables can be specified with the C<-minlables> flag:

 'org'    =~ $RE{'dns'}{'domain'}                  # match
 'org'    =~ $RE{'dns'}{'domain'}{-minlables => 2} # no match
 'co.org' =~ $RE{'dns'}{'domain'}{-minlables => 2} # match

The C<-rfc> flag can be used to specify any of the three rule sets.  The
pragmatic ruleset discussed earlier is labled as C<hybrid>.

=cut

pattern name   => [qw(dns domain -rfc= -minlables= -wildcard=)],
		create => sub {
			my $pattern = domain(@_);
			
			return qq/(?=^.{1,255}\$)(?k:$pattern)/;
		}
		;	


sub domain {
	my $flags = $_[1];
	
	my $sep   = '\.';
	
	my $letter        = '[a-zA-Z]';
	my $let_dig       = '[a-zA-Z0-9]';
	my $let_dig_hyp   = '[-a-zA-Z0-9]';
	
	my %lables = (
		1035   => "(?:$letter(?:$let_dig|$let_dig_hyp\{1,61}$let_dig)?)",
		2181   => '[^.]{1,63}',
		hybrid => '[a-zA-Z0-9_-]{1,63}'
	);
	
	$flags->{'-rfc'} ||= $DEFAULT_RFC;
	
	my $lable = $lables{$flags->{'-rfc'}} || die("Unknown DNS RFC: $flags->{'-rfc'}");
	
	if ($flags->{'-rfc'} ne 2181 && exists $flags->{'-wildcard'} && not defined $flags->{'-wildcard'}) {
		$lable = "(?:\\*|$lable)";
	}

	my $quant = '*';
	if ($flags->{'-minlables'}) {
		$quant = '{' . ($flags->{'-minlables'} - 1) . ',}';
	}
	
	return qq/(?:$lable$sep)$quant$lable$sep?/;
}		


=head2 $RE{'dns'}{'data'}{'a'}

Matches the data section of an A record.  This is a dotted decimal representation
of a IPv4 address.

=cut

pattern name   => [qw(dns data a)],
		create => qq/(?k:$RE{'net'}{'IPv4'})/;
		
		
=head2 $RE{'dns'}{'data'}{'cname'}

Matches the data section of a CNAME record.  This pattern accepts the same
flags as C<$RE{'dns'}{'domain'}>.

=cut

pattern name   => [qw(dns data cname -rfc= -minlables= -wildcard=)],
		create => sub {
			my $cname = domain(@_);
			
			return qq/(?k:$cname)/;
		}
		;	
	

=head2 $RE{'dns'}{'data'}{'mx'}

Matches the data section of a MX record.  This pattern accepts the same
flags as C<$RE{'dns'}{'domain'}>.

If keep is turned on, then the C<$n> variables are filled as follows:

=over 2

=item $1

The entire data section.

=item $2

The preference.

=item $3

The exchange.

=back

=cut

pattern name   => [qw(dns data mx -rfc= -minlables= -wildcard=)],
		create => sub {
			my $exchange = domain(@_);
			my $prefence = $RE{'dns'}{'int16'};
			
			return qq/(?k:(?k:$prefence)\\s+(?k:$exchange))/;
		}
		;


=head2 $RE{'dns'}{'data'}{'soa'}

Matches the data section of a MX record.  This pattern accepts the C<-rfc>
flag.

If keep is turned on, then the C<$n> variables are filled as follows:

=over 2

=item $1

The entire data section.

=item $2

The mname.

=item $3

The rname.

=item $4

The serial number.

=item $5

The refresh time interval.

=item $6

The retry time interval.

=item $7

The expire time value.

=item $8

The minimum TTL.

=back

=cut

pattern name   => [qw(dns data soa -rfc=)],
	    create => sub {
	    	my $flags = $_[1];
	    	
			my $mname = domain(@_);
			my $rname = do {
				local $flags->{'-minlables'} = 2;
				
				domain(@_);
			};
			
			my $serial  = $RE{'dns'}{'int32'};
			my $refresh = $RE{'dns'}{'int32'};
			my $retry   = $RE{'dns'}{'int32'};
			my $expire  = $RE{'dns'}{'int32'};
			my $minimum = $RE{'dns'}{'int32'};
			
			my $regexp = qq/(?k:
				(?k:$mname)
				\\s+
				(?k:$rname)
				\\s+
				(?k:$serial)
				\\s+
				(?k:$refresh)
				\\s+
				(?k:$retry)
				\\s+
				(?k:$expire)
				\\s+
				(?k:$minimum)
			)/;
			
			
			$regexp =~ s/\s+//g;
			
			return $regexp;
		}
		;
			

=head1 TODO

Several RR data patterns are missing:

 HINFO
 MB
 MG
 MINFO
 MR
 NULL (easy!)
 PTR  
 TXT
 WKS
 RP
 LOC 
 AAAA
 OPT
 SRV
 DNAME

and more.

Patterns for whole RR records, TTLs, classes, and types are missing.

Ideally patterns for the various compenent of a data section would
be provided, for example to match the mname section of a soa record:

 $RE{'dns'}{'data'}{'soa'}{'mname'}
 
The author is not sure that the C<$RE{'dns'}{'data'}{'rr'}> namespace is
needed, perhaps C<$RE{'dns'}{'rr'}> would suffice.

=head1 AUTHOR

Chris Reinhardt
cpan@triv.org

=head1 COPYRIGHT

Copyright (c) 2003 Chris Reinhardt.

All rights reserved.  This program is free software; you may redistribute
it and/or modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Regexp::Common>, perl(1).

=cut



1; 
__END__

