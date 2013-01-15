#!/usr/bin/perl -w
#
# GPLv3 - (c) Babel srl www.babel.it
#
# Author: rpolli@babel.it
#
# a simple iostat replacement returning some more statistics
#
# This script uses the info exposed in /proc/diskstats
# and make some calculations using the following definition:
#
#     - Usage = usage_time / sampling_time
#     - Arrival = sum of all iops in sampling_time (r+w)
#     - operation_time = sum of all the time spent in iops (r+w)time
#
# Little's Law (to calculate L)
#     - L = A * W    # queue_lenght = arrival_rate * average_wait_time
# Usage Law (to calculate S)
#     - U = S * X    # usage = service_time * exit_rate (thruput)
#
use strict;
use diagnostics;

use Getopt::Long;
use Term::ANSIColor;
use Term::ANSIColor qw(:constants);
use Carp ();
local $SIG{__WARN__} = \&Carp::cluck;

#local $Term::ANSIColor::AUTORESET = 1;

our $SECTOR_SIZE = 512;

sub colorize($$) {    #string, colorize
    my $ret = shift;
    $ret = sprintf( '%s%s%s', color(shift), $ret, color("reset") );
    return $ret;
}

sub usage(@) {

    if ( defined $1 ) {
        print "Error: $1\n\n";
    }
    print "usage: $0 <interval> <device> <pagination> [options]\n" . "\n"
      . "Like iostat but showing some more statistics\n" . "\n"
      . "options:\n"
      . " -i : print data in iostat format\n"
      . " -s : print size in sectors instead of KiloBytes\n"
      . " -m : print size in megabytes instead of KiloBytes\n"

      . "\n";
    exit 1;
}

# parse input parameters
my ( $interval, $device, $pagination ) = @ARGV;
my ( $iostat_like, $verbose, $megabytes, $output_in_sectors, $size_factor,
    $help );

usage("missing interval")   unless ($interval);
usage("missing device")     unless ($device);
usage("missing pagination") unless ($pagination);

# print headers every pagination lines
my $ln = 0;

my %disks = ();
my @prev_0 = ( 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 );

#my ($a, $b, $c, $dev, $r, $rrqm, $rsec, $rtime, $w, $wrqm, $wsec, $wtime, $iop, $iotime, $avg_iotime);
my (
    $a, $b, $c,
    $dev,
    $r, $rrqm, $rsec, $rtime,    # read stats
    $w, $wrqm, $wsec, $wtime,    # write stats
    $iop, $iotime, $avg_iotime,  # ops and time stats
    $util,                       # computed: %util
    $avg_sz, $avg_r_sz, $avg_w_sz,    # computed: averages
    $rs,       $ws,          # computed: read/writes per second
    $rw,       $rwsec,       # computed: total iop and sectors
    $rwtime,   $time,        # computed: total time spent in io, included wait
    $avg_r_tm, $avg_w_tm,    # computed: average times
    $svctm, $await, $avg_q_sz, $avg_q_tm,    # computed: average service times
    $dirty                                   # dirty buffers
);

#
# formatters
#
format IOSTAT =
@<<<<<<<      @>>>>>>> @>>>>>>> @>>>>>>> @>>>>> @>>>>>>> @>>>>>>> @>>>>>> @>>>>>>>> @>>>>>> @>>>>> @>>>>>
$dev, $rrqm, $wrqm , $r, $w, $rsec, $wsec, $avg_sz, $avg_q_sz, $await, $svctm, $util
.
format IOSTAT_TOP =
Device:         rrqm/s   wrqm/s     r/s     w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
.

format SUMMARY_TOP=
def             rwtime             iop          iotime
.
format SUMMARY =
@<<<<< @<<<<<<< @<<<<< @<<<<<
$dev, $rwtime, $iop, $iotime
.

our $fmt_stdout = "%-6s "    #dev is right-aligned
  . colorize( "%9.2f %9.2f ", "red" ) . "%9.2f %9.2f "    #iops merged and total
  . colorize( "%9.2f %9.2f %9.2f %9.2f", "blue" )         #time, iops, iotime
  . "%9.2f %9.2f "                                        #avgtime util
  . "%9.2f %9.2f %9.2f "                                  # avg r/w size
  . colorize( "%9.2f %9.2f", "green" )                    #avg r/w time
  . "\n";

our $fmt_rw_merged      = colorize( "%8.2f %8.2f ", "red" );
our $fmt_rw_merged_head = colorize( "%8s %8s ",     "red" );

our $fmt_rw_ops      = "%7.2f %7.2f ";
our $fmt_rw_ops_head = "%7s %7s ";

our $fmt_avg_rwt_size      = colorize( "%10.2f %10.2f %10.2f", "blue" );
our $fmt_avg_rwt_size_head = colorize( "%8s %8s %8s",       "blue" );

our $fmt_avg_rwt_time      = colorize( "%9.2f %9.2f %9.2f", "green" );
our $fmt_avg_rwt_time_head = colorize( "%9s %9s %9s",       "green" );

our $fmt_util = "%8.2f";

#
# Get Options
#
my $result = GetOptions(
    'i' => \$iostat_like,          # print iostat-like output
    'm' => \$megabytes,            # print merged stats
    's' => \$output_in_sectors,    # print size in sectors

    'v'      => \$verbose,
    'h|help' => \$help             # help verbose
);

usage() if ($help);
$iostat_like = defined $iostat_like;

$~ = "IOSTAT" if ($iostat_like);

if ( defined $megabytes ) {
    $size_factor = 2048;
}
elsif ( defined $output_in_sectors ) {
    $size_factor = 1;
}
else {
    $size_factor = 2;
}

sub get_dirty_buffers() {
    my $ret;
    open( MI, "<", "/proc/meminfo" );
    while (<MI>) {
        if (m/Dirty.*:\s*([0-9]+ kB)/) {
            $ret = $1;
            last;
        }
    }
    close(MI);
    return $ret;
}

#
# Play my game
#
$ln = 0;
while (1) {
    open( DS, "<", "/proc/diskstats" );
    while (<DS>) {
        if ( $_ =~ m/\b$device/ ) {

            #print "\tline: $_";
            my @new = split(/\s+/);
            my @tmp = @new;
            (
                $a, $b, $c, $dev, $r, $rrqm, $rsec, $rtime, $w, $wrqm, $wsec,
                $wtime, $iop, $iotime, $avg_iotime
            ) = @tmp;
            if ( not defined $disks{$dev} ) {
                $disks{$dev} = \@prev_0;
                next;
            }
            my @prev = @{ $disks{$dev} };

            # first diskstat fields are garbage
            for ( my $i = 4 ; $i <= $#tmp ; $i++ ) {
                $tmp[$i] = ( $tmp[$i] - $prev[$i] ) / $interval;
            }

            # parse again values and do some math
            (
                $a, $b, $c, $dev, $r, $rrqm, $rsec, $rtime, $w, $wrqm, $wsec,
                $wtime, $iop, $iotime, $avg_iotime
            ) = @tmp;

            #
            # Total ops and timing
            #
            $rw     = $r + $w;
            $rwtime = $wtime + $rtime;
            $rwsec  = $rsec + $wsec;

            #
            # Average request size, in sector: total, read, write
            #

            $avg_sz   = ($rw) > 0 ? ($rwsec) / ($rw) : 0;
            $avg_r_sz = $r > 0    ? ( $rsec / $r )   : 0;
            $avg_w_sz = $w > 0    ? ( $wsec / $w )   : 0;

            #
            # Average time (queue + service): total, read, write
            #
            $avg_r_tm = $r > 0  ? ( $rtime / $r )   : 0;
            $avg_w_tm = $w > 0  ? ( $wtime / $w )   : 0;
            $avg_q_tm = $rw > 0 ? ( $rwtime / $rw ) : 0;
            $await    = $avg_q_tm;

            #
            # Average time (service): uses the iotime value taken from diskstats
            #
            $svctm = $rw > 0 ? ( $iotime / $rw ) : 0;

            #
            # Service thruput: io operations per second, included queue
            #
            $ws = $wtime ? ( $w / $wtime ) : 0;
            $rs = $rtime ? ( $r / $rtime ) : 0;

# percent time spent in IO. from milliseconds to seconds, then in % -> ( x / 1000 ) * 100
            $util = $iotime / 10;

# From Little's Law: QueueLength = ArrivalFrequence * WaitTime
#	ArrivalFrequence = $rw (incoming operation per second)
#	WaitTime = $rwtime / $rw ( average milliseconds of each operation in the queue)
#	QueueLength = $rwtime / 1000
            $avg_q_sz = $rwtime / 1000;

            #
            # Eventually do further math
            #
            $iotime     *= 1;
            $avg_iotime *= 1;

            my $dirty = get_dirty_buffers();

            if ( $r >= 0 ) {

                #
                # Colorize output
                #
                die("unset") unless defined($dev);
                die("unset") unless defined($avg_sz);
                die("unset") unless defined($avg_r_sz);
                die("unset") unless defined($avg_w_sz);

                #
                # Use FORMAT | WRITE if iostat_like
                #
                if ($iostat_like) {
                    write;
                }
                else {

                    #
                    # Use custom formatting
                    #
                    printf( "%-6s ", $dev );

                    # read / write stats
                    printf( $fmt_rw_merged . $fmt_rw_ops, $rrqm, $wrqm, $r,
                        $w );

                    # read write size
                    printf( $fmt_rw_ops,
                        $rsec / $size_factor,
                        $wsec / $size_factor );

                    # average read write size
                    printf( $fmt_avg_rwt_size,
                        $avg_r_sz / $size_factor,
                        $avg_w_sz / $size_factor,
                        $avg_sz / $size_factor );

                    printf( $fmt_avg_rwt_time, $avg_r_tm, $avg_w_tm, $await );

                    printf( $fmt_rw_ops, $svctm, $util );

                    printf($dirty);
                    print "\n";

           #                 printf( $fmt_stdout,
           #                     $dev,      $rrqm,       $wrqm,     $r,
           #                     $w,        $rtime,      $wtime,    $rwtime,
           #                     $iotime,   $avg_iotime, $util,     $avg_sz,
           #                     $avg_r_sz, $avg_w_sz,   $avg_r_tm, $avg_w_tm );

                }
            }

            $disks{$dev} = \@new;
        }
    }
    close(DS);
    sleep($interval);
}
continue {

    (
        $a,        $b,      $c,        $dev,      $r,
        $rrqm,     $rsec,   $rtime,    $w,        $wrqm,
        $wsec,     $wtime,  $rwtime,   $iotime,   $avg_iotime,
        $util,     $avg_sz, $avg_r_sz, $avg_w_sz, $avg_r_tm,
        $avg_w_tm, $svctm,  $avg_q_tm, $await,    $avg_q_sz,
        $dirty
      )
      = qw(a b c dev
      r rrqm rsec rtime
      w wrqm wsec wtime
      ttime iotime avg_iotime
      util avg_sz avg_r_sz avg_w_sz
      avg_r_tm agv_w_tm svctm avgqu-tm
      await avgqu-sz dirty
    );

    if ( ( $ln % $pagination ) == 0 ) {
        if ($iostat_like) {
            write;

        }
        else {
            printf( "%-6s ", $dev );

            # read / write stats
            printf( $fmt_rw_merged_head. $fmt_rw_ops_head,
                $rrqm, $wrqm, $r, $w );

            # read write size
            #   add measure unit
            my $unit = "kBs";
            $unit = "MBs" if ($megabytes);
            $unit = "sec" if ($output_in_sectors);
            printf( $fmt_rw_ops_head , "r " . $unit, "w " . $unit );

            # average read write size
            printf( $fmt_avg_rwt_size_head,
                $avg_r_sz . $unit,
                $avg_w_sz . $unit,
                $avg_sz . $unit
            );

            printf( $fmt_avg_rwt_time_head, $avg_r_tm, $avg_w_tm, $await );

            printf( $fmt_rw_ops_head, $svctm, $util );

            printf($dirty);
            print "\n";
        }
    }

    $ln++;
}
