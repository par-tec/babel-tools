babel-tools
===========

A set of script for testing postfix.

Before committing format code with:
 # perltidy -b *.pl

Files:
 * bb-check.pl - various checks on postfix configuration: missing and unused files, mismatching comments, missing libraries ... 
 * bb-iostat.pl - a re-implementation of iostat with dis-aggregated stats for read/write
 * bb-maillog.pl - a simple postfix log parser to be used in conjuction with tail. Nicely test your mail routes.
 * bb-sendmail.pl - send mail to your MX or MSA using custom template files. Supports authentication LOGIN PLAIN

Peace,
R.
