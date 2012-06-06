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
use strict;
use diagnostics;
use Getopt::Std;

my $verbose = 0;

sub usage() {
    print "usage: $0 options [-c config_dir | -f file]\n"
      . "Allowed options:\n"
      . "\t-u	check for unused files, present in current directory but not listed in postfix|filters configuration\n"
      . "\t-m	check for missing files, listed in postfix configuration but not present in the current directory\n"
      . "\t-t	check for possible errors in postfix configuration files\n";
    exit(1);
}

# find files referenced in postfix configuration but missing
# in the current directories
sub find_missing_files(@) {    #files

    print "Missing files:\n" . "-------------------------------\n";

    # pattern used to match configuration files. May not be exhaustive
    our $file_pattern = qq|\\s(/[A-z0-9_][/A-z0-9_.]+[A-z0-9])|;

    my $a;

    foreach my $file (@_) {
        my $errors = 0;
        next if ( $file =~ m|/\.\.?$| );
        open FH, "<", $file;
        printf "Scanning file: %-30s...", $file;
        while (<FH>) {
			next if ( m/^\s*#/ );
            # match every file, even more files on the same line
            while ( $_ =~ m|$file_pattern|g ) {
                $a = $1;

                #    $a =~ s|/etc/postfix|.|g;

                # print unexistent files
                if ( not -e $a ) {
                    $errors++;
                    printf( "\n\tmissing file: %30s", $a );
                    next;
                }

                # scripts must be executable
                #  print error and continue
                #  with syntax checking
                if ( $a =~ m/\.(sh|pl|py|php)$/ and not -x $a ) {
                    $errors++;
                    printf( "\n\tscript not executable: %30s", $a );
                }

                # check perl syntax
                if ( $a =~ m/\.pl$/ and not `perl -c -- $a` ) {
                    $errors++;
                    printf( "\n\tscript with errors: %30s", $a );
                    next;
                }
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
	
    print "Unused files:\n" . "-------------------------------\n";

    my @skip_files =
      qw|\.\.?$ main.cf master.cf post-install postfix-script postfix-files|;
    my $re_skip_files = join( "|", @skip_files );
    
    foreach my $file (@_) {
        next if ( $file =~ m/$re_skip_files/ );
        
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

    print "Typos in configuration files:\n"
      . "-------------------------------\n";

    foreach my $file (@_) {

        next if ( $file =~ m|/\.\.?$| );
        next unless ( $file =~ m!join("|", @files_to_check)! );

        my ($nl, $lno, $err ) = qw(0 1 "");
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
sub check_sasl(@) { # files
    my $re_sasl_client      = qq/^[^#]+smtp_sasl_auth_enable\\s\*=\\s\*yes/;
    my $re_sasl_server      = qq/^[^#]+smtpd_sasl_auth_enable\\s\*=\\s\*yes/;
    my $re_sasl_client_type = qq/^[^#]+smtp_sasl_type/;
    my $re_sasl_server_type = qq/^[^#]+smtpd_sasl_type/;
    my @sasl_type_client    = ();
    my @sasl_type_server    = ();


    print "SASL support:\n" . "-------------------------------\n";
    foreach my $f (@_) {

		# check only main|master .cf
		next unless ( "$f" =~ m/main.cf|master.cf/ );

        open( FH, "<", $f ) or die("cannot open $f");
        while (<FH>) {
            printf "\tSASL client enabled\n" if (m/$re_sasl_client/);
            printf "\tSASL server enabled\n" if (m/$re_sasl_server/);

            push( @sasl_type_client, $1 ) if (m/$re_sasl_client_type\s*=\s*(.+)/);
            push( @sasl_type_client, $1 ) if (m/$re_sasl_server_type\s*=\s*(.+)/);
        }
        close FH;

    }

	my @sasl_libs = ();
    if ( -e "/usr/bin/rpm" ) {
	  @sasl_libs = `rpm -qa \*sasl\*;`;
    } elsif ( -e "/usr/bin/dpkg" ) {
	  foreach my $lib  (`dpkg -l \*sasl\*;`) {
		next unless (/^ii\s+([^ ]+)/);
		push(@sasl_libs, $1);
	  }
	  
    }

    printf "SASL packages: %s", join
    

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

	print "\n";
}

sub main {
    my $postfix_dir = "/etc/postfix";
    my @files       = ();
    my %options     = ();
    getopts( "mtuvc:f:", \%options );

    usage() if not scalar( keys(%options) );

    $verbose     = ( defined $options{'v'} );
    $postfix_dir = $options{'c'} if ( $options{'c'} );
    @files       = ( $options{'f'} ) if ( $options{'f'} );

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
    find_unused_files($postfix_dir, @files);
    check_typos(@files);
	
    exit 0;
}

&main;
