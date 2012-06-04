#!/usr/bin/perl -w
#
#License  GPLv3
# A simple script to analyze postfix configuration files
# 2012 (c) Babel srl
#

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
sub find_missing_files(@) {

    # pattern used to match configuration files. May not be exhaustive
    our $file_pattern = qq|\\s(/[A-z0-9_][/A-z0-9_.]+[A-z0-9])|;

    my $a;

    foreach my $file (@_) {
        next if ( $file =~ m|/\.\.?$| );
        open FH, "<", $file;
        print "scanning file: $file\n" if ($verbose);
        while (<FH>) {

            # match every file, even more files on the same line
            while ( $_ =~ m|$file_pattern|g ) {
                $a = $1;

                #    $a =~ s|/etc/postfix|.|g;

                # print unexistent files
                print "missing file: $1 in $file\n" unless ( -e $a );
            }
        }
        close FH;
    }
}

# find files unmentioned in postfix configuration
sub find_unused_files(@) {    #list of files to check
    my @skip_files =
      qw|\.\.?$ main.cf master.cf post-install postfix-script postfix-files|;
    my $skip_files_re = join( "|", @skip_files );
    foreach my $file (@_) {
        next if ( $file =~ m/$skip_files_re/ );
        grep { !/.svn/ } `grep -ril -- "$file" . `
          or print("unused file: $file\n");
    }
}

# check for possible typos in main.cf and master.cf
sub check_typos(@_) {         #list of files to check
    my $spaces_before_vars = qq/^\s+[A-z0-9]+=/;
    my $trailing_comment   = qq/^\s*[A-z].*\s*#/;
    foreach my $file (@_) {
        next if ( $file =~ m|/\.\.?$| );
        my $nl = 0, $lno = 1, $err = "";
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
        print "file: $file \t\t\ko$nl lines with syntax errors\n" if ($nl);
        print "file: $file \t\tok\n" if ( !$nl );
    }
}

sub main {
    my $postfix_dir = "/etc/postfix";
    my @files       = ();
    my %options     = {};
    getopts( "mtuvc:f:", \%options );

    usage() if not scalar( keys(%options) );

    $verbose     = 1                 if defined $options{'v'};
    $postfix_dir = $options{'c'}     if ( $options{'c'} );
    @files       = ( $options{'f'} ) if ( $options{'f'} );

    if ( $#files < 0 ) {
        opendir( DIR, $postfix_dir ) or die("missing directory $postfix_dir.");
        foreach my $f ( readdir(DIR) ) {
            push( @files, "$postfix_dir/$f" );
        }
        closedir(DIR);
    }

    die("no files to analyze. Check your configuration directory!")
      if ( $#files <= 0 );

    print "analyzing $#files files...\n";

    find_missing_files(@files) if $options{'m'};
    find_unused_files(@files)  if $options{'u'};
    check_typos(@files)        if $options{'t'};

    exit 0;
}

&main;
