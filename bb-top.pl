#!/usr/bin/perl -w
#
# GPLv3 - (c) Babel srl www.babel.it
#
# Author: rpolli@babel.it
#

# a tool for monitoring memory, sockets, and threads useful to
# benchmarking multithread servers
use strict;
use diagnostics;

use Getopt::Long;
use Term::ANSIColor;
use Term::ANSIColor qw(:constants);
use Carp ();
local $SIG{__WARN__} = \&Carp::cluck;

#local $Term::ANSIColor::AUTORESET = 1;

our $PAGE_SIZE = 4096;

sub colorize($$) {    #string, colorize
    my $ret = shift;
    $ret = sprintf( '%s%s%s', color(shift), $ret, color("reset") );
    return $ret;
}

sub usage(@) {

    if ( defined $1 ) {
        print "Error: $1\n\n";
    }
    print
      "usage: $0  -i <interval> -t <pagination> -p <pid1> [-p <pid2> ...] \n"
      . "\n"
      . "Print some memory and socket related statistics from:\n"
      . "\t  - /proc/\$PID/status\n"
      . "\t  - /proc/\$PID/net/tcp\n" . "\n"

      . "\n";
    exit 1;
}

# print headers every pagination lines
my $ln = 0;
my (
    $name, $state, $tgid, $tid, $ppid, $tracerpid, $uid, $gid, $fdsize,
    $groups,    # 0-9
    $vmpeak, $vmsize, $vmlck, $vmpin, $vmhwm, $vmrss, $vmdata, $vmstk, $vmexe,
    $vmlib,     #10-19
    $vmpte, $vmswap, $threads,                             #20-22
    $sigq, $sigpnd, $shdpnd, $sigblk, $sigign, $sigcgt,    #23-28
    $capinh,       $capprm,            $capeff,       $capbnd,            #39-32
    $cpus_allowed, $cpus_allowed_list, $mems_allowed, $mems_allowed_list, #33-36
    $voluntary_ctxt_switches, $nonvoluntary_ctxt_switches                 #37-38
);
my $sockets = 0;

#
# formatters
#
format VMSTAT =
@<<<<<<<      @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>> @>>>>> @>>>>> 
$tid, $name, $vmpeak , $vmrss, $vmsize, $vmdata, $vmswap, $threads, $sockets
.

format VMSTAT_TS =
@<<<<<<<<<<<<   @<<<<<<<      @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>>>> @>>>>> @>>>>> @>>>>> 
time(), $tid, $name, $vmpeak , $vmrss, $vmsize, $vmdata, $vmswap, $threads, $sockets
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

our $fmt_avg_rwt_size      = colorize( "%8.2f %8.2f %8.2f", "blue" );
our $fmt_avg_rwt_size_head = colorize( "%8s %8s %8s",       "blue" );

our $fmt_avg_rwt_time      = colorize( "%9.2f %9.2f %9.2f", "green" );
our $fmt_avg_rwt_time_head = colorize( "%9s %9s %9s",       "green" );

our $fmt_util = "%8.2f";

#
# Get Options
#
my ( $verbose, $megabytes, $output_in_pages, $size_factor, $help, $pid );
my ( $interval, $pagination, @pids );

my $result = GetOptions(

    #   'm' => \$megabytes,         # print merged stats
    #   's' => \$output_in_pages,   # print size in sectors
    'i=s'    => \$interval,      # cycle every i seconds
    't=s'    => \$pagination,    # print headers every p lines
    'p=s'    => \@pids,          # list of pids
    'v'      => \$verbose,
    'h|help' => \$help           # help verbose
);

usage("missing interval")   unless ($interval);
usage("missing pids")       unless (@pids);
usage("missing pagination") unless ($pagination);

usage() if ($help);

print "Running $0 with: \n"
  . "\tinterval $interval\n"
  . "\tpagination $pagination\n";

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

sub pid_status($) {    #pid
    my $pid = shift;
    my %ret = ();

    my $path = "/proc/$pid/status";
    open( DS, "<", $path ) or die("can't open $path");
    while (<DS>) {
        my @new = split(/:\t+/);

        # use MB for kB entries
        $new[1] = int( $new[1] / 1024 ) if ( $new[1] =~ s/\s+kB[\s\r\n]+//i );

        $ret{ lc( $new[0] ) } = $new[1];
    }
    close(DS);
    return \%ret;
}

# count established sockets
sub pid_tcp_sockets($) {    # pid
    my $pid = shift;

    # from linux/tcp_states.h
    my %tcp_states = (
        'TCP_ESTABLISHED' => '01',
        TCP_SYN_SENT      => 2,
        TCP_SYN_RECV      => 3,
        TCP_FIN_WAIT1     => 4,
        TCP_FIN_WAIT2     => 5,
        TCP_TIME_WAIT     => 6,
        TCP_CLOSE         => 7,
        TCP_CLOSE_WAIT    => 8,
        TCP_LAST_ACK      => 9,
        TCP_LISTEN        => 10
    );
    my $re_established = qq!:[0-9A-F]{4} $tcp_states{'TCP_ESTABLISHED'} !;
    my $sock_status    = 0;

    my $path = "/proc/$pid/net/tcp";
    open( DS, "<", $path ) or die("can't open $path");
    while (<DS>) {
        $sock_status++ if ( $_ =~ m!$re_established! );
    }
    close(DS);
    return $sock_status;
}

#
# Play my game
#

$~ = "VMSTAT_TS";

$ln = 0;
while (1) {

    foreach $pid (@pids) {
        my %mem_status = %{ pid_status($pid) };
        ( $tid, $name, $vmpeak, $vmrss, $vmsize, $vmdata, $vmswap, $threads ) =
          map ( { $mem_status{$_} }
            qw( pid name vmpeak vmrss vmsize vmdata vmswap threads ) );

        $sockets = pid_tcp_sockets($pid);
        write;
    }
    sleep($interval);
}
continue {

    (
        $name, $state, $tgid, $tid, $ppid, $tracerpid, $uid, $gid, $fdsize,
        $groups,    # 0-9
        $vmpeak, $vmsize, $vmlck, $vmpin, $vmhwm, $vmrss, $vmdata, $vmstk,
        $vmexe,  $vmlib,  #10-19
        $vmpte, $vmswap, $threads,                             #20-22
        $sigq, $sigpnd, $shdpnd, $sigblk, $sigign, $sigcgt,    #23-28
        $capinh, $capprm, $capeff, $capbnd,                    #39-32
        $cpus_allowed, $cpus_allowed_list, $mems_allowed,
        $mems_allowed_list,                                    #33-36
        $voluntary_ctxt_switches, $nonvoluntary_ctxt_switches  #37-38
        , $sockets
      )
      = qw(
      name state tgid pid ppid tracerpid uid gid fdsize groups
      vmpeak vmsize vmlck vmpin vmhwm vmrss vmdata vmdata vmexe vmlib
      vmpte vmswap threads
      sigq sigpnd shdpnd sigblk sigign sigcgt
      capinh capprm capeff capbnd
      cpus_allowed cpus_allowed_list mems_allowed mems_allowed_list
      voluntary_ctxt_switches nonvoluntary_ctxt_switches
      sockets
    );

    if ( ( $ln % $pagination ) == 0 ) {
        write;
    }

    $ln++;
}
