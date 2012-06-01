#!/usr/bin/perl -w
use strict;
use Net::SMTP;
use Getopt::Std;
use MIME::Base64;

my $verbose = 0;

sub dprint($) {
    print shift if $verbose;
}

sub usage() {
    print "Usage: $0 -u username -p password -n nonce\n"
      . "Create a token string for smpt authentication\n" . "\n";

    exit(1);
}

sub plain_string($$) {    #username password
    my ( $username, $password ) = @_;

    $username =~ s|@|\@|;    #escape @

    my $ret = encode_base64( "\000" . $username . "\000" . $password );
    chomp($ret);
    return ($ret);

}

sub test_plain() {
    my ( $u, $p ) = qw/jms1@jms1.net not.my.real.password/;
    my $expect_1 = 'AGptczFAam1zMS5uZXQAbm90Lm15LnJlYWwucGFzc3dvcmQ=';

    my $ret = plain_string( $u, $p );
    dprint("ret: [$ret]\n");
    die("fail test_plain") if ( $ret ne $expect_1 );

}

sub main() {
    my %opts = ();
    getopts(
        "hvt"           #help verbose test
          . "u:p:n:"    # credentials
        , \%opts
    );

    usage() if ( defined $opts{'h'} or not scalar( keys(%opts) ) );
    $verbose = defined $opts{'v'};
    my $i    = 0;
    my @args = ();
    foreach my $field ( 'u', 'p', 'n' ) {
        $args[$i] = $opts{$field} if ( defined( $opts{$field} ) );
        $i++;
    }
    my ( $username, $password, $nonce ) = @args;

    if ( defined $opts{'t'} ) {
        test_plain();
        exit(0);
    }

    print "LOGIN STRING: ", plain_string( $username, $password );
}
&main();

