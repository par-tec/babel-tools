#!/usr/bin/perl -w
# (c) Babel srl
# License:  GPLv3
# 
# Author: rpolli@babel.it
#
# 

while(<>) {
    print "$1\t\t$2\t\tREJECT\n" if ($_ =~ m/.*reject.*from=<(.*?)> to=<(.*?)>.*/ ); 

    $mid{$1}="$2\t\t$3" if ($_ =~ m/.*: ([A-Z0-9]+): warning.* from=<(.*?)> to=<(.*?)>/ );

    print "$mid{$1}\t\tOK\n" if ($_ =~ m/.*: ([A-Z0-9]+): to=.*status=sent/);

}
