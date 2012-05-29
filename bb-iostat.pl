#!/usr/bin/perl -w

sub usage() {
    print "usage: $0 interval device pagination\n" . "\n"
      . "Like iostat but showing some more statistics\n" . "\n";
    exit 1;
}

# parse input parameters
my ($interval, $device, $pagination) = @ARGV;

# print headers every pagination lines
my $ln = 0; 

sub my_iostat(){
# pipe iostat to perl
open( DATE, "iostat -x $interval -d $device |" );
while (<DATE>) {
    chop();
    if (/^[a-z]/) {
        my ($device, $rrqm, $wrqm, $r, $w, $rsec, $wsec, $avgrq_sz, $avgqu_sz, $await , $svctm ) = split;

        # time spent in queue is wait-service time
        $queue_time = $await-$svctm;
        $queue_ratio = ( $svctm > 0 ? $queue_time / $svctm :  $svctm  );

        # separate counters for read and write
        $avg_r_sz = ($r>0)		? $rsec/$r : $r ;
        $avg_w_sz =($w>0)	? $wsec/$w : $w;

        # dump
        printf ("$_ %0.2f\t%0.2f\t%0.2f\t%0.2f\n", $queue_time, $queue_ratio, $avg_r_sz, $avg_w_sz);
        $ln++;
    }
    elsif ( /^D/ and not( $ln % $pagination ) ) { 
	  print "$_ qtim\tqrat\tavgr_sz\tagvw_sz\n";
    }
}
close(DATE);
}


my %disks={};
my @prev_0 = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
$ln = 0;
while(1) {
  open(DS, "<", "/proc/diskstats");
  while(<DS>) {
	if ($_ =~ m/\b$device/) {
	  #print "\tline: $_";
	  my @new = split(/\s+/);
	  my @tmp = @new;
	  my ($a, $b, $c, $dev, $r, $rrmq, $rsec, $rtime, $w, $wrmq, $wsec, $wtime, $iops, $iotime, $avg_iotime) = @tmp;
	  if  (not defined $disks{$dev}) {
	  $disks{$dev}=\@prev_0 ;
	  next;
	  }
	  my @prev = @{$disks{$dev}};

	  # first diskstat fields are garbage
	  for (my $i=4;  $i<=$#tmp; $i++) {
		$tmp[$i] = ($tmp[$i] -  $prev[$i]) / $interval;
	  }

	  # parse again values and do some math
	  ($a, $b, $c, $dev, $r, $rrmq, $rsec, $rtime, $w, $wrmq, $wsec, $wtime, $iops, $iotime, $avg_iotime) = @tmp;
	  my $avg_sz = ($w+$r)>0 ? ($wsec + $rsec) / ($w +$r) : 0;
	  my $avg_r_sz = $r>0 ? ($rsec / $r) : 0;
	  my $avg_w_sz = $w>0 ? ($wsec / $w) : 0;
	  my $ws = $wtime ? ($w / $wtime) : 0;
	  my $util = $iotime / 10; # percent time spent in IO. from milliseconds to seconds, then in % -> ( x / 1000 ) * 100 
	  $iotime *= 1;
	  $avg_iotime *= 1;
	  if ($r >= 0) {
format STDOUT =
@<<<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<< @<<<<<
$dev, $rrmq, $wrmq, $r, $w, $rtime, $wtime, $iops, $iotime, $avg_iotime, $util, $avg_sz,$avg_r_sz,$avg_w_sz
.

	  write;
	  sprintf ("%s\t"
	  ."%0.2f\t%0.2f\t%0.2f\t%0.2f\t"		# read
	  ."%0.2f\t%0.2f\t%0.2f\t%0.2f\t"		# write
	  ."%0.2f\t%0.2f\t%0.2f\t%0.2f\t"					# iops
	  ."%0.2f\t%0.2f\t%0.2f\n", $dev,		 #avg r+w
	  $r, $rrmq, $rsec, $rtime,
	  $w, $wrmq, $wsec, $wtime,
	  $iops, $iotime, $avg_iotime, $util,
	  $avg_sz,$avg_r_sz,$avg_w_sz);

	  }

	   $disks{$dev} = \@new;
	}
  }
  close(DS);
  sleep($interval);
} continue {
  ($a, $b, $c, $dev, $r, $rrmq, $rsec, $rtime, $w, $wrmq, $wsec, $wtime, $iops, $iotime, $avg_iotime) = qw($a, $b, $c, $dev, $r, $rrmq, $rsec, $rtime, $w, $wrmq, $wsec, $wtime, $iops, $iotime, $avg_iotime);
  write if not ($ln % $pagination);
  
	sprintf "dsk\tr\t rrmq\t rsec\t rtime\t"
	  ." w\t wrmq\t wsec\t wtime\t"
	  ." iops\t iotime\t avg_io\t\%util\t"
	  ."avg_sz\tavg_r_sz\tavg_r_sz\n";# if  not ($ln % $pagination);
	  
  $ln++;
  }
