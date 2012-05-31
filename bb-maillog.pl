#!/usr/bin/perl -w
# (c) Babel srl
# License:  GPLv3
#
# Author: rpolli@babel.it
#
#
use Getopt::Std;

our $re_qid     = qq|[^:]+|;
our $re_field   = qq|[^:]+|;
our $re_mail    = qq|[^>]+|;
our $re_relay   = qq|[^,]+|;
our $re_comment = qq|[^;]+|;
our $re_status  = qq|[^ ]+|;
our $re_reject =
qq|$re_field: NOQUEUE: (reject): [^:]+: [^:]+: ($re_comment); from=<($re_mail)> to=<($re_mail)>.*|;
our $re_accept = qq|$re_field: ($re_qid): from=<($re_mail)>, size|;
our $re_sent =
qq|$re_field: ($re_qid): to=<($re_mail)>, relay=($re_relay), .* status=($re_status) |;
our $re_removed = qq|$re_field: ($re_qid): removed|;

sub parser() {
    my %maillog = ();
    while (<>) {
        my ( $from, $to, $relay, $comment, $mid, $qid ) = qw/X X X X X X/;

        format STDOUT_TOP =
From                            To                                 Qid           Relay                                      Comment
.
        format STDOUT =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<
$from, $to, $qid, $relay, $comment
.

        if ( $_ =~ m/$re_reject/ ) {
            ( $from, $to, $status, $comment ) = ( $3, $4, $1, $2 );
            write;
        }
        elsif ( $_ =~ m/$re_accept/ ) {
            ( $qid, $from ) = ( $1, $2 );
            $maillog{$qid} = $from;
        }
        elsif ( $_ =~ m/$re_sent/ ) {
            ( $qid, $to, $relay, $status ) = ( $1, $2, $3, $4 );
            if ( defined( $maillog{$qid} ) ) {
                $from = $maillog{$qid};
                write;
            }
        }
        elsif ( $_ =~ m/$re_removed/ ) {
            undef( $maillog{$qid} );
        }

    }
}

sub test_re() {
    my $test_str_1 =
'May 31 09:53:35 test-fe1 postfix/smtpd[3061]: NOQUEUE: reject: RCPT from internal.example.net[99.88.77.66]: 553 5.7.1 <segreteria@babel.it>: Sender address rejected: not logged in; from=<segreteria@babel.it> to=<segreteria@babel.it> proto=ESMTP helo=<snix>';
    my $test_str_2 =
'May 31 08:30:54 test-fe1 postfix/qmgr[12699]: 7CD8E730020: from=<rpolli@babel.it>, size=85300, nrcpt=1 (queue active)';
    my $test_str_3 =
'May 31 08:30:54 test-fe1 postfix/smtp[16667]: 04C49370001: to=<antani@example.it>, relay=10.0.0.1[10.0.0.1]:10025, delay=1.8, delays=0.61/0.01/0/1.2, dsn=2.0.0, status=sent (250 OK, sent 5FD7101D_19399_99500000 7CD8E730020)';
    my $test_str_4 =
'May 31 08:30:55 test-fe1 postfix/smtp[16669]: 7CD8E730020: to=<antani1@example.it>, relay=examplemx2.example.it[222.33.44.555]:25, delay=0.8, delays=0.17/0.01/0.43/0.19, dsn=2.0.0, status=sent(250 ok:  Message 2108406157 accepted)';
    my $test_str_4_1 =
'May 31 08:30:55 test-fe1 postfix/smtp[16669]: 7CD8E730020: to=<antani2@example.it>, relay=examplemx2.example.it[222.33.44.555]:25, delay=0.8, delays=0.17/0.01/0.43/0.19, dsn=2.0.0, status=sent(250 ok:  Message 2108406157 accepted)';
    my $test_str_5 =
      'May 31 08:30:55 test-fe1 postfix/smtp[16669]: 7CD8E730020: removed';
    my $test_str_4_2 =
'May 31 08:30:55 test-fe1 postfix/smtp[16669]: 7CD8E730020: to=<antani2@example.it>, relay=examplemx2.example.it[222.33.44.555]:25, delay=0.8, delays=0.17/0.01/0.43/0.19, dsn=2.0.0, status=sent(250 ok:  Message 2108406157 accepted)';

    my @test = (
        $test_str_1,   $test_str_2, $test_str_3, $test_str_4,
        $test_str_4_1, $test_str_5, $test_str_4_2
    );

    $test_str_1 =~ m/$re_reject/;
    ( $from, $to, $status, $comment, $relay ) = ( $3, $4, $1, $2, "" );
    write;
    die("fail") unless ( $from and $to and $status and $comment );

    $test_str_2 =~ m/$re_accept/;
    ( $qid, $from ) = ( $1, $2 );
    write;
    die("fail") unless ( $from and $qid );

    $test_str_3 =~ m/$re_sent/;
    ( $qid, $to, $relay, $status ) = ( $1, $2, $3, $4 );
    write;
    die("fail") unless ( $from and $qid );

    $test_str_4 =~ m/$re_sent/;
    ( $qid, $to, $relay, $status ) = ( $1, $2, $3, $4 );
    write;
    die("fail") unless ( $from and $qid );

    $test_str_5 =~ m/$re_removed/;
    ($qid) = ($1);
    write;
    die("fail") unless ($qid);

    my $log = "";
    foreach my $t (@test) {
        $log .= $t . "\n";
    }

    #print "$log";
    my $ret = `echo "$log" | ./$0 `;
    print "$ret";
    die("test failed: $ret") unless $ret;

}

sub simple_parser() {
    while (<>) {
        print "$1\t\t$2\t\tREJECT\n"
          if ( $_ =~ m/.*reject.*from=<(.*?)> to=<(.*?)>.*/ );
        $mid{$1} = "$2\t\t$3"
          if ( $_ =~ m/.*: ([A-Z0-9]+): warning.* from=<(.*?)> to=<(.*?)>/ );
        print "$mid{$1}\t\tOK\n"
          if ( $_ =~ m/.*: ([A-Z0-9]+): to=.*status=sent/ );
    }
}

sub usage() {
    print "Usage: $0 [-t]  < maillog \n";
    print "\tor\n";
    print "Usage: tail -f /var/log/maillog | $0  \n";
    print
"Parse a postfix maillog file, printing a simple table with the following fields:\n";
    print "From	To	QId	Relay	Status	Comment\n";
    print "\n";

    exit 1;
}

sub main() {
    our %options = ();
    getopts( "ht", \%options );

    if ( defined $options{'t'} ) {
        test_re();
    }
    elsif ( defined $options{'h'} ) {
        usage();
    }
    else {
        parser();
    }

}

&main;
