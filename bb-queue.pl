#!/usr/bin/perl -w
#
# GPLv3 - (c) Babel srl www.babel.it
#
# Author: rpolli@babel.it
#

#
# Print some simple queue statistics
#

use strict;
use warnings;
use diagnostics;

use HTTP::Date;
use Getopt::Long;
use Data::Dumper;
use POSIX qw/ strftime /;
use File::Temp qw/ tempfile /;

my $verbose = 0;

sub dprint($) {
    print STDERR shift if $verbose;
}

sub usage(@) {

    if ( defined $1 ) {
        print "Error: $1\n\n";
    }
    print "usage: $0 -i <interval> -q <queue> -p <pagination> [options]\n"
      . "\n"
      . "Parses postqueue output printing some statistics\n" . "\n"
      . "options:\n"
      . " -i : interval between two checks\n"
      . " -p : print header every p lines\n"

      #\TODO      . " -q : check only a given queue\n"
      . " -h : this help\n"
      . " -t : print timestamp\n"
      . " -v : a bit of debugging output\n"
      . " -g : create a gnuplot graph. Just refresh to see the data\n"
      . " --test : test parser\n" . "\n";

    exit(1);
}

my $postqueue = "/usr/sbin/postqueue";

# Results
my %count_template = (
    'total'  => 0,
    'active' => 0,
    'hold'   => 0,

    'size'  => 0,
    'first' => time(),
    'last'  => time(),

    # active queue info
    'active_size'  => 0,
    'active_first' => time(),
    'active_last'  => time(),

    'wtime'      => 0,
    'avg_wtime'  => 0,
    'usage_time' => 0,
    'thruput'    => 0,
    'domains'    => { 'localhost' => 0 }

);

# Some regular expressions
my $re_queue_type = qq|[*!]|;
my $re_qid        = qq|[A-Z0-9]+|;
my $re_size       = qq|[0-9]+|;
my $re_from       = qq|[^ ]+|;
my $re_date       = qq|\\w{3}\\s+\\w{3}\\s+\\d+\\s+\\d+:\\d+:\\d+|;
my $re_postqueue =
  qq|($re_qid)($re_queue_type?)\\s+($re_size)\\s+($re_date)\\s+($re_from)|;

my $fmt_datetime = "%d-%m-%Y %H:%M:%S";

sub safe_div($$) {    # numerator, denominator
    my $n = shift;
    my $d = shift;
    return ( $d > 0 ) ? ( $n / $d ) : 0;
}

#
# parser function
#
sub parser($) {       #file handle
    my $que   = shift;
    my %count = %count_template;
    $count_template{'first'} = time();
    $count_template{'last'}  = time();

    print Dumper(%count) if ($verbose);
    while (<$que>) {
        chomp;
        if ( $_ =~ m/$re_postqueue/ ) {
            my ( $qid, $qtype, $size, $date, $from ) = ( $1, $2, $3, $4, $5 );
            $count{'total'}++ if defined $1;

            next unless defined $2;

            # Get queue type
            if ( $qtype eq "*" ) {
                $count{'active'}++;
            }
            elsif ( $qtype eq "!" ) {
                $count{'hold'}++;
            }
            else {
                $count{'deferred'}++;
            }

            # get mail size
            $count{'size'} += $3 if defined $3;

            # get time
            my $t = str2time($4);
            $count{'first'} = ( $count{'first'} < $t ) ? $count{'first'} : $t;
            $count{'last'}  = ( $count{'last'} > $t )  ? $count{'last'}  : $t;
            $count{'avg_wtime'} += time() - $t;

            # Active queue stats
            if ( $qtype eq "*" ) {
                $count{'active_first'} =
                  ( $count{'first'} < $t ) ? $count{'first'} : $t;
                $count{'active_last'} =
                  ( $count{'last'} > $t ) ? $count{'last'} : $t;
                $count{'active_avg_wtime'} += time() - $t;
                $count{'active_size'} += $size;
            }

            # get domain stats
            if ( defined $from ) {
                $from =~ s/.*@//;
                $count{'domains'}{$from}++;
            }

        }
    }

    #
    # Average time in queues
    #
    $count{'avg_wtime'} = safe_div( $count{'avg_wtime'}, $count{'total'} );
    $count{'active_avg_wtime'} =
      safe_div( $count{'active_avg_wtime'}, $count{'active'} );

    #
    # wtime - time elapsed since which the queue is used
    # usage_time - time interval in which the queue received items
    #
    $count{'wtime'}        = time() - $count{'first'};
    $count{'usage_time'}   = $count{'last'} - $count{'first'};
    $count{'active_wtime'} = time() - $count{'active_first'};

    #
    # Little's Law: QueueLength = Thruput * WaitTime
    #  the same for the size
    #
    $count{'mps'} = safe_div( $count{'total'}, $count{'wtime'} );

    $count{'Bps'}        = safe_div( $count{'size'},   $count{'wtime'} );
    $count{'active_mps'} = safe_div( $count{'active'}, $count{'active_wtime'} );
    $count{'active_Bps'} =
      safe_div( $count{'active_size'}, $count{'active_wtime'} );

    return \%count;
}

sub gnuplot_header($) {    # tmpfile
    my $tmpfile = shift;
    my $ret     = <<END
	
f = "$tmpfile"
set xlabel "time"
set key outside bottom
set ylabel "%"
set autoscale
set grid
set xdata time
set format x "%H:%M"
set timefmt "$fmt_datetime"
set ylabel "items"
set title "Postfix Queue Stats"
set style fill solid 0.5 border

set log y

plot f using 1:3 title "tot" with boxes lc 1,   \\
  f using 1:4 title "active" with boxes,   \\
  f using 1:5 title "KB" with lines,       \\
  f using 1:7 title "mps" with lines lw 2,   \\
  f using 1:11 title "mps*" with lines lw 2,   \\
  f using 1:8 title "qusage" with lines, \\
  f using 1:9 title "KBps" with lines lw 2, \\
  f using 1:12 title "KBps*" with lines lw 2 \\

END
      ;

    return $ret;
}

sub main() {
    my ( $argc, @argv ) = ( $#ARGV, @ARGV );
    my $que;
    my $i = 0;
    my ( $help, $queue, $test, $gnuplot, $tmpfile, $time );
    my ( $interval, $pagination, $domain, $outfile_fh ) = ( 5, 24, 0, *STDOUT );

    my @fields =
      qw|total active KB     delay mps  usg   KBps  avg_wtime tput*  KBps*|;
    my @fmt_fields_data =
      qw|%-5d  %5d    %12.2f %6d   %5.2f   %3.2f %8.2f %8.2f     %5.2f  %5.2f|;
    my @fmt_fields_head =
      qw|%-5s  %5s    %12s   %6s   %5s     %3s   %8s   %8s       %5s    %5s|;

    my $fmt_data = join( "\t", @fmt_fields_data ) . "\n";
    my $fmt_head = join( "\t", @fmt_fields_head ) . "\n";

    my $result = GetOptions(
        'i=s'  => \$interval,     # server options
        'q=s'  => \$queue,
        'p=s'  => \$pagination,
        'test' => \$test,
        't'    => \$time,

        'v'         => \$verbose,
        'd'         => \$domain,
        'g|gnuplot' => \$gnuplot,

        'h|help' => \$help        # help verbose
    );

    test() if defined $test;

    usage() if ( $help or $argc < 1 );

    #
    # output data to a tmpfile and run gnuplot
    #
    if ( defined $gnuplot ) {

        # gnuplot requires tracing time
        $time = 1;

        # we're going to fork, man!
        $SIG{CHLD} = 'IGNORE';

        ( $outfile_fh, $tmpfile ) =
          tempfile( "/tmp/bb-queue-gnuplot.XXXXXX", UNLINK => 1 );
        dprint( "tmpfile: " . $tmpfile );

        printf $outfile_fh "%s " . $fmt_data,
          (
            strftime( $fmt_datetime, localtime() ),
            qw/ 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1/
          );
        my $cmd = "echo '" . gnuplot_header($tmpfile) . "' | gnuplot -p";
        dprint( "gnuplot cmd: " . $cmd );
        system($cmd );

        print STDERR "Hey man, just REFRESH your graph to see the data!\n";
    }

    my $command = sprintf("$postqueue -p ");
    my %curr    = %count_template;
    my %prev;
    while (1) {
        open( $que, "$postqueue -p |" ) or die $!;
        my $h_curr = parser($que);
        %prev = %curr;
        %curr = %{$h_curr};

        my $speed =
          $prev{'total'} ? ( $curr{'total'} - $prev{'total'} ) / $interval : 0;

        my $usg = safe_div( $curr{'usage_time'}, $curr{'wtime'} );

        # gnuplot does not want headers
        if ( not defined($gnuplot) and !( $i++ % $pagination ) ) {
            printf $outfile_fh ( "%-22s", 'time' ) if ( defined $time );
            printf $outfile_fh ( $fmt_head, @fields );
        }

        printf $outfile_fh "%-22s", strftime( $fmt_datetime, localtime() )
          if ( defined $time );

        printf $outfile_fh
          $fmt_data,
          $curr{'total'}, $curr{'active'}, $curr{'size'} / 1000,
          $curr{'wtime'},
          $curr{'mps'}, $usg, $curr{'Bps'} / 1000,
          $curr{'avg_wtime'},
          $curr{'active_mps'}, $curr{'active_Bps'} / 1000,
          ;

        # from qSummary.pl
        if ($domain) {
            my %domains = %{ $curr{'domains'} };
            foreach my $key (
                reverse sort { $domains{$a} <=> $domains{$b} }
                keys %domains
              )
            {
                print $outfile_fh "\t\t$key\t$domains{$key}\n";
            }
        }
        close($que);
        sleep($interval);
    }

}

#
# Tests
#
sub test() {

    sub test_hash_1() {
        my %domains = %{ $count_template{'domains'} };

        my @keys = keys %domains;
        die("domains") if ( not @keys );

        foreach my $k (@keys) {
            print "k: $k, " . $domains{$k} . "\n";
        }

    }

    sub test_re_1() {
        my $t_postqueue = <<END
4908384CA2*     240 Tue Jul 10 19:10:21  rpolli\@babel.it
                                         fabio\@ast.it
                                         gnarwl\@localhost.localdomain

CF88B84C92*     240 Tue Jul 10 19:10:20  rpolli\@babel.it
                                         fabio\@ast.it

1910B84C9B*     240 Tue Jul 10 19:10:21  rpolli\@babel.it
                                         fabio\@ast.it
                                         gnarwl\@localhost.localdomain
END
          ;
        my $t_postqueue_1 =
          '4908384CA2*     240 Tue Jul 10 19:10:21  rpolli@babel.it';
        my $t_postqueue_2 =
          '4908384CA2!     240 Tue Jul 10 19:10:21  rpolli@babel.it';
        my $x_from = 'rpolli@babel.it';
        my $x_date = "Tue Jul 10 19:10:21";
        my $x_qid  = "4908384CA2";
        {
            $t_postqueue_1 =~ $re_postqueue;

            my ( $qid, $qtype, $size, $date, $from ) = ( $1, $2, $3, $4, $5 );
            die("mismatched qid")           unless ( $qid   eq $x_qid );
            die("mismatched qtype")         unless ( $qtype eq "*" );
            die("mismatched from: [$from]") unless ( $from  eq $x_from );

            die("mismatched size") unless ( $size == 240 );
            die("mismatched date") unless ( $date eq $x_date );
        }

        {
            $t_postqueue_2 =~ m/$re_postqueue/;

            my ( $qid, $qtype, $size, $date, $from ) = ( $1, $2, $3, $4, $5 );
            die("mismatched qid")           unless ( $qid  eq $x_qid );
            die("mismatched from: [$from]") unless ( $from eq $x_from );

            die("mismatched qtype") unless ( $qtype eq "!" );
            die("mismatched size")  unless ( $size == 240 );
            die("mismatched date")  unless ( $date  eq $x_date );
        }
        return;

    }
    print "Tests\n";
    test_re_1;
    test_hash_1;

    exit 0;

}

#
# Main
#
&main;

