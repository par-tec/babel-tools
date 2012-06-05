#!/usr/bin/perl -w
# (c) Babel srl
# License:  GPLv3
#
# Author: rpolli@babel.it
#
# Parses maillog writing infos on mail
#
# TODO use a convenience representation of ips and qids as integer
#
use strict;
use diagnostics;
use Getopt::Std;
use Term::ANSIColor;
use Term::ANSIColor qw(:constants);

my %months = (
    'Jan' => 1,
    'Feb' => 2,
    'Mar' => 3,
    'Apr' => 4,
    'May' => 5,
    'Jun' => 6,
    'Jul' => 7,
    'Aug' => 8,
    'Sep' => 9,
    'Oct' => 10,
    'Nov' => 11,
    'Dec' => 12,

    'jan' => 1,
    'feb' => 2,
    'mar' => 3,
    'apr' => 4,
    'may' => 5,
    'jun' => 6,
    'jul' => 7,
    'aug' => 8,
    'sep' => 9,
    'oct' => 10,
    'nov' => 11,
    'dec' => 12,

);

#
# Regular expressions: building blocks
#
our $re_qid      = qq|[^:]+|;
our $re_field    = qq|[^:]+|;
our $re_mail     = qq|[^>]+|;
our $re_relay    = qq|[^,]+|;
our $re_comment  = qq|[^;]+|;
our $re_status   = qq|[^ ]+|;
our $re_hostname = qq|[^ ]+|;
our $re_process  = qq|[^:]+|;
our $re_header   = qq|[A-z]+\\s+[0-9]+\\s+[0-9]+:[0-9]+:[0-9]+\\s+[^:]+|;
our $re_header_full =
  qq|^(\\w+)\\s+(\\d+)\\s+(\\d+:\\d+:\\d+) ($re_hostname) ($re_process)|;

our $re_reject =
qq|($re_header): ($re_qid): (reject): $re_field: ($re_comment); from=<($re_mail)> to=<($re_mail)>.*|;
our $re_accept = qq|($re_header): ($re_qid): from=<($re_mail)>, size|;
our $re_sent =
qq|($re_header): ($re_qid): to=<($re_mail)>, relay=($re_relay), .* status=($re_status) |;
our $re_removed = qq|($re_header): ($re_qid): removed|;

our %strip_from_comment = ( '5.7.1' => qq|<.*?>|, '5.1.1' => qq|<.*?>|);

#
# Colorize output
#
sub colorize($$) {    #string, colorize
    my $ret = shift;
    $ret = sprintf( '%s%s%s', color(shift), $ret, color("reset") );
    return $ret;
}

#
# Parse Postfix log file
# \param numeric - don't print relay hostnames, just ip
# \param logfile - logfile to parse
#
sub parser($$) {      #numeric logfile
    my ( $numeric, $logfile ) = @_;

    # initialize formatter vars to non-empty fields
    my (
        $from, $to,     $relay, $comment, $mid,
        $qid,  $header, $date,  $status,  $server_name
    ) = qw/= = X = = = = = = =/;

    #
    # Formatters
    #
    format SIMPLE_TOP =
From                                 To                                      Qid         Relay                   Comment
.

    format SIMPLE =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$from, $to, $qid, $relay, $comment
.

    format DATE_TOP =
Date             From                                 To                                      Qid         Relay                  Comment
.

    format DATE =
@<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$date, $from, $to, $qid, $relay, $comment
.

    format FULL_TOP =
Date             From                                 To                                      Qid         Relay                  Comment               Server
.

    format FULL =
@<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<  @<<<<<<<<<<<<<<<
$date, $from, $to, $qid, $relay, $comment, $server_name
.

    # A maillog hash for storing qid
    my %maillog = ();

    #
    # Eventually open log file
    #
    *IF = *STDIN;
    if ( defined($logfile) and ( -e $logfile ) ) {
        open( IF, "<", "$logfile" );
    }

    #
    # Start parsing
    #
    while (<IF>) {

        # those vars should always been set
        ( $from, $to, $relay, $comment, $mid, $qid, $date, $server_name ) =
          qw/= = X = = = = =/;

        #
        # Always print greppable errors on console
        #
        if ( $_ =~ m/error/i ) {
            print colorize( "ERROR: $_", "red" );
        }

        #
        # Collect mail data, and in case of sent or reject, print them
        #
        if ( $_ =~ m/$re_reject/ ) {
            ( $header, $qid, $status, $comment, $from, $to ) =
              ( $1, $2, $3, $4, $5, $6 );
            $header =~ m/$re_header_full/;
            $date = sprintf( "%02d-%02d %s", $months{$1}, $2, $3 );
            $server_name = $4;

            #
            # Reduce comment length: should be configurable
            #
            foreach my $p (keys(%strip_from_comment)) {
			  $comment =~ s|$strip_from_comment{$p}||g if ($comment =~ m|$p|);
            } 
            write;
        }
        elsif ( $_ =~ m/$re_accept/ ) {
            ( $header, $qid, $from ) = ( $1, $2, $3 );
            $maillog{$qid} = $from;
        }
        elsif ( $_ =~ m/$re_sent/ ) {
            ( $header, $qid, $to, $relay, $status ) = ( $1, $2, $3, $4, $5 );
            if ( defined( $maillog{$qid} ) ) {

                # Format date
                $header =~ m/$re_header_full/;
                $date = sprintf( "%02d-%02d %s", $months{$1}, $2, $3 );
                $server_name = $4;

                # strip hostnames if $numeric
                $relay =~ s/.*\[/[/g if ($numeric);

                #
                # get from from %maillog and print
                #
                $from = $maillog{$qid};
                write;
            }
        }
        elsif ( $_ =~ m/$re_removed/ ) {
            undef( $maillog{$qid} );
        }

    }

    close(IF);
}

sub test_re() {

    my ( $from, $to, $relay, $comment, $mid, $qid, $header, $date, $status ) =
      qw/= = X = = = = = =/;

    my $test_str_1 =
'May  1 09:53:35 test-fe1 postfix/smtpd[3061]: NOQUEUE: reject: RCPT from internal.example.net[99.88.77.66]: 553 5.7.1 <segreteria@babel.it>: Sender address rejected: not logged in; from=<segreteria@babel.it> to=<segreteria@babel.it> proto=ESMTP helo=<snix>';
    my $test_str_1_1 =
'May 31 08:30:54 test-fe1 postfix/qmgr[12699]: CEB10370001: from=<example@babel.it>, size=85300, nrcpt=1 (queue active)';
    my $test_str_1_2 =
'May 31 18:21:36 spcp-fe1 postfix/smtpd[25279]: CEB10370001: reject: RCPT from dynamic-adsl.clienti.example.org[192.168.9.1]: 550 5.1.1 <lan@internetspa.it>: Recipient address rejected: User unknown in virtual mailbox table; from=<robipolli@internetspa.it> to=<lan@internetspa.it> proto=ESMTP helo=<internetspa.it>';
    my $test_str_1_3 =
'Jun  5 15:14:43 spcp-fe1 postfix/smtpd[3504]: NOQUEUE: reject: RCPT from dynamic-adsl.clienti.example.org[192.168.9.1]: 451 4.3.5 Server configuration problem; from=<me@example.it> to=<you@example.net> proto=ESMTP helo=<me2you>';

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
        $test_str_1, $test_str_1_1, $test_str_1_2, $test_str_1_3,
        $test_str_2, $test_str_3,   $test_str_4,   $test_str_4_1,
        $test_str_5, $test_str_4_2
    );
    my $test_no = 1;

    {
        print "test " . $test_no++ . "\n";
        $test_str_1 =~ m/$re_reject/;
        my ( $header, $qid, $status, $comment, $from, $to, $relay ) =
          ( $1, $2, $3, $4, $5, $6, "" );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail")
          unless ( $from
            and $to
            and $status
            and $comment
            and $header
            and $qid );
    }
    {
        print "test " . $test_no++ . "\n";
        $test_str_1_2 =~ m/$re_reject/;
        my ( $header, $qid, $status, $comment, $from, $to, $relay ) =
          ( $1, $2, $3, $4, $5, $6, "" );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail") unless ( $from and $to and $status and $comment and $qid );
    }
    {
        print "test " . $test_no++ . "\n";
        $test_str_1_3 =~ m/$re_reject/;
        my ( $header, $qid, $status, $comment, $from, $to, $relay ) =
          ( $1, $2, $3, $4, $5, $6, "" );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail") unless ( $from and $to and $status and $comment and $qid );
    }
    {
        print "test " . $test_no++ . "\n";
        $test_str_2 =~ m/$re_accept/;
        my ( $header, $qid, $from ) = ( $1, $2, $3 );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail") unless ( $from and $qid );
    }
    {
        print "test " . $test_no++ . "\n";
        $test_str_3 =~ m/$re_sent/;
        my ( $header, $qid, $to, $relay, $status ) = ( $1, $2, $3, $4, $5 );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail") unless ( $from and $qid );
    }
    {
        print "test " . $test_no++ . "\n";
        $test_str_4 =~ m/$re_sent/;
        my ( $header, $qid, $to, $relay, $status ) = ( $1, $2, $3, $4, $5 );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail") unless ( $from and $qid );
    }
    {
        print "test " . $test_no++ . "\n";
        $test_str_5 =~ m/$re_removed/;
        my ( $header, $qid ) = ( $1, $2 );
        print "TEST: ", $header, $qid, $status, $comment, $from, $to, $relay,
          "\n";
        die("fail") unless ($qid);
    }
    my $log = "";
    foreach my $t (@test) {
        $log .= $t . "\n";
    }

    #print "$log";
    print "Running a full parsing test\n";
    my $ret = `echo "$log" | ./$0 `;
    print "$ret";
    die("test failed: $ret") unless $ret;

    $ret = `echo "$log" | ./$0 -d`;
    print "$ret";
    die("test failed: $ret") unless $ret;
}

sub simple_parser() {
    my %mid = ();
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
    print "From To      QId     Relay   Status  Comment\n";
    print "\n";
    print "Unless -f. comments are shortened using the %strip_from_comment table. You can customize it as you like.";
    print "\n";
	print "Options:";
    print " -t test script\n";
    print " -h print this screen\n";
    print " -n don't print resolved domains, just ip\n";
    print " -d print date\n";
    print " -f full logging: with date and server name\n";
    print "\n";

    exit 1;
}

sub main() {
    our %options = ();
    getopts( "dfhntl:", \%options );
    my $numeric    = ( defined $options{'n'} );
    my $print_date = ( defined $options{'d'} );
    my $full       = ( defined $options{'f'} );
    my $logfile    = $options{'l'};

    $~ = "SIMPLE";
    $^ = "SIMPLE_TOP";
    if ($print_date) {
        $~ = "DATE";
        $^ = "DATE_TOP";
    }
    elsif ($full) {
        $~ = "FULL";
        $^ = "FULL_TOP";
        %strip_from_comment = ();
    }

    if ( defined $options{'t'} ) {
        test_re();
    }
    elsif ( defined $options{'h'} ) {
        usage();
    }
    else {
        parser( $numeric, $logfile );
    }

}

&main;

