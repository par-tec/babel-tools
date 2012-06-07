#!/usr/bin/perl -w
#
#License  GPLv3
# A simple script to analyze postfix configuration files
# 2012 (c) Babel srl
#
# - starts from main.cf and master.cf
# - Verify existing files
# - Verify
#

# && 	# not be comments or empty, and
#			( 
#			!/[=,]\s*$/ || 			# be complete lines (eg. don't end with = or , )
#			#s/^([^#]+[=,])\s*\n/$1/  	# or the join of incomplete lines (eg. if line ends with [=,] join with the upper one
#			s/^(.+)\n\s+/$1 /ms  	# or the join of incomplete lines (eg. if line ends with [=,] join with the upper one
#		)
use strict;
use diagnostics;
use Getopt::Std;
use File::Find;

my $verbose = 0;

sub usage() {
    print "usage: $0 options [-c config_dir | -f file]\n"
      . "Allowed options:\n"
      . "\t-c	use the given postfix configuration directory\n"
      . "\t-f	check the given files\n"
      . "\t-v	verbose output\n"
      . "\t-u	normalize the given configuration file (postconf format)\n";
    exit(1);
}

# find files referenced in postfix configuration but missing
# in the current directories
sub find_missing_files(@) {    #files

    print "\nMissing files:\n" . "-------------------------------\n";

    # pattern used to match configuration files. May not be exhaustive
    our $file_pattern = qq|[ :"'](/[A-z0-9_\-][/A-z0-9_.\-]+[A-z0-9])|;
    my @skip_files =
      qw|\.\.?$ post-install postfix-script postfix-files LICENSE TLS_LICENSE license prng_exch|;
    my $re_skip_files = join( "|", @skip_files );

	my $a;

    foreach my $file (@_) {
        my $errors = 0;
        next if ( $file =~ m|$re_skip_files| );

		# Skip directories
		next if (-d $file);

        open FH, "<", $file;
        printf "Scanning file: %-60s...", $file;
        while (<FH>) {
            next if ( $_ =~ m/^\s*#/);

			#print $_ if ($verbose);
            # match every file, even more files on the same line
            while ( $_ =~ m|$file_pattern|g ) {
                $a = $1;
				print "\n\tfile: $a" if ($verbose);
				
                # print unexistent files
                if ( not -e $a ) {
                    $errors++;
                    printf( "\n\tmissing file: %60s", $a );
                    next;
                }

                # scripts must be executable
                #  print error and continue
                #  with syntax checking
                if ( $a =~ m/.*\.(sh|pl|py|php)$/ and not -x $a ) {
                    $errors++;
                    printf( "\n\tscript not executable: %60s", $a );
                }

                # check perl syntax
                if ( $a =~ m/.*\.pl$/)  {
                 if ( not `perl -c -- $a` ) {
                    $errors++;
                    printf( "\n\tscript with errors: %60s", $a );
				  } else {
					  printf( "\n\tscript syntax ok: %60s", $a);
				  }
                }
                                    next;
            }
        }
        close FH;

        printf( "%3s\n", $errors ? "" : "OK" );
    }
    print "\n\n";
}

# find files unmentioned in postfix configuration
sub find_unused_files(@) {    #postfix_dir, list of files to check
    my $postfix_dir = shift;

    print "\nUnused files:\n" . "-------------------------------\n";

    my @skip_files =
      qw|\.\.?$ main.cf master.cf post-install postfix-script postfix-files LICENSE TLS_LICENSE license prng_exch|;
    my $re_skip_files = join( "|", @skip_files );

    foreach my $file (@_) {
        next if ( $file =~ m/$re_skip_files/ );
        next if ( -d $file );

        $file =~ s|/+|/|g;
        grep { !/.svn/ } `grep -ril -- "$file" "$postfix_dir" `
          or print("unused file: $file\n");
    }
}

# check for possible typos in main.cf and master.cf
sub check_typos(@) {    #list of files to check
    my $spaces_before_vars = qq/^\\s+[A-z0-9]+=/;
    my $trailing_comment   = qq/^\\s*[A-z].*\\s*#/;
    my @files_to_check     = qw|main.cf master.cf|;

    print "\nTypos in configuration files:\n"
      . "-------------------------------\n";

    foreach my $file (@_) {

        next if ( $file =~ m|/\.\.?$| );
        next unless ( $file =~ m!join("|", @files_to_check)! );

        my ( $nl, $lno, $err ) = qw(0 1 "");
        open FH, $file or die("cannot open file $file");

        while (<FH>) {
            $err = "space before vars" if ( $_ =~ m/$spaces_before_vars/ );
            $err = "trailing comment"  if ( $_ =~ m/$trailing_comment/ );

            if ( $err ne "" ) {
                print "$file:$lno: $_";
                $nl++;
            }
        }
        continue {
            $lno++;
            $err = "";
        }
        close(FH);
        print "file: $file \t\tko$nl lines with syntax errors\n" if ($nl);
        print "file: $file \t\tok\n" if ( !$nl );
    }
    print "\n";
}

#
# Checks main.cf and master.cf for sasl
#
sub check_sasl(@) {    # files
    my $re_sasl_client      = qq/^[^#]+smtp_sasl_auth_enable\\s\*=\\s\*yes/;
    my $re_sasl_server      = qq/^[^#]+smtpd_sasl_auth_enable\\s\*=\\s\*yes/;
    my $re_sasl_client_type = qq/^[^#]+smtp_sasl_type/;
    my $re_sasl_server_type = qq/^[^#]+smtpd_sasl_type/;
    my @sasl_type_client    = ();
    my @sasl_type_server    = ();
    my ( $sasl_client, $sasl_server ) = ( 0, 0 );

    print "\nSASL support:\n" . "-------------------------------\n";
    foreach my $f (@_) {

        # check only main|master .cf
        next unless ( "$f" =~ m/main.cf|master.cf/ );

        open( FH, "<", $f ) or die("cannot open $f");
        while (<FH>) {
            $sasl_client = 1 if (m/$re_sasl_client/);
            $sasl_server = 1 if (m/$re_sasl_server/);

            push( @sasl_type_client, $1 )
              if (m/$re_sasl_client_type\s*=\s*(.+)/);
            push( @sasl_type_client, $1 )
              if (m/$re_sasl_server_type\s*=\s*(.+)/);
        }
        close FH;

    }
    printf "\tSASL client enabled\n" if ($sasl_client);
    printf "\tSASL server enabled\n" if ($sasl_server);

    #
    # Check client sasl support
    #
    my @postconf_client = `postconf -A`;
    foreach my $a (@sasl_type_client) {
        next if ( $a =~ m/join("|",@postconf_client)/ );
        printf "\tunsupported SASL client type: $a\n";
    }

    #
    # Check server sasl support
    #
    my @postconf_server = `postconf -a`;
    foreach my $a (@sasl_type_server) {
        next if ( $a =~ m/join("|",@postconf_server)/ );
        printf "\tunsupported SASL client type: $a\n";
    }

    #
    # Check SASL library
    #
    my @sasl_libs = ();
    my $rpm       = "/bin/rpm";
    my $dpkg      = "/usr/bin/dpkg";

    if ( -e $rpm ) {
        @sasl_libs = `$rpm -qa \*sasl\*;`;
    }
    elsif ( -e $dpkg ) {
        foreach my $lib (`$dpkg -l \*sasl\*;`) {
            next unless ($lib =~ m/^ii\s+([^ ]+)/);
            push( @sasl_libs, $1 );
        }
    }

    if ( @sasl_libs > 0 ) {
        printf "\tSASL packages: %s\n", join( ",", @sasl_libs );
        printf "\tCAVEAT: YOUR POSTFIX MAY NEED OTHER PACKAGES!\n"
        ."\t\tIf you have issues with SASL please check you have \n"
        ."\t\tall the required .so libraries\n";
    }
    else {
        printf "\tcannot determine SASL packages\n";
    }

    print "\n";
}

#
# Uncomment and normalize main.cf
#
sub normalize_cf($){ #file to normalize
	my $re_blank_comments = qq/^\\s*(#|\$)/;

	my ($file) = @_;

	open (FH, "<", $file) or die ("cannot open file: $file.");
	
	# strip blank and comments
	my @ret = grep { !/$re_blank_comments/  } <FH>;
	close (FH);

	#
	# Join lines starting with blanks with the previous one
	# 
	my $p = "";
	my $c = "";
	foreach my $line (@ret) {
	foreach  my $c (split //, $line) {
		next if ($c eq "\n");
		print $p if ( ($c !~ m/\s+/)  and ($p eq "\n"));
		
		# replace multiple space with a single " "
		next if ($c =~ '\s' and $p =~ '\s');
		print ($c =~ '\s' ? " " : $c) ;
	} continue { $p = $c; }
}
}

sub main {
    my $postfix_dir = "/etc/postfix";
    my @files       = ();
    my %options     = ();
    getopts( "vu:c:f:", \%options );

    usage() if not scalar( keys(%options) );

    $verbose     = ( defined $options{'v'} );
    $postfix_dir = $options{'c'} if ( $options{'c'} );
    @files       = ( $options{'f'} ) if ( $options{'f'} );
    
    if (defined $options{'u'}) {
	normalize_cf($options{'u'});
	exit(0);
    }
    
	

    if ( $#files < 0 ) {
        opendir( DIR, $postfix_dir )
          or die("missing directory $postfix_dir.");
        foreach my $f ( readdir(DIR) ) {

            # strip double slashes
            my $s = "$postfix_dir/$f";
            $s =~ s|/+|/|g;
            push( @files, $s );
        }
        closedir(DIR);
    }

    die("no files to analyze. Check your configuration directory!")
      if ( $#files <= 0 );

    print "Postfix Configuration Checker: directory $postfix_dir\n\n";

    check_sasl(@files);

    find_missing_files(@files);
    find_unused_files( $postfix_dir, @files );
    check_typos(@files);

    exit 0;
}

&main;
