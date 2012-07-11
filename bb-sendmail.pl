#!/usr/bin/perl -w
#
# GPLv3 - (c) Babel srl www.babel.it
#
# Author: rpolli@babel.it
#
# TODO send multiple attachments
#
use strict;
use Net::SMTP;
use Getopt::Long;
use MIME::Base64;

my $verbose = 0;

sub dprint($) {
    print shift if $verbose;
}

sub usage() {
    die
"Usage: $0 -s server:port -f from -t to -c cc -b bcc -m message -a auth_type -u user -p pass -j subject -d data_file\n"
      . "\n"
      . "Send an email using the given parameters\n"
      . "  -h print this screen\n"
      . "  -v verbosely dump smtp session\n"
      . "  -i send i-times the same email on the same connection\n"
      . "  -s smtp server - eg. mx.babel.it:25\n"
      . "  -e EHLO string\n"
      . "  -f sender - set MAIL FROM\n"
      . "  -t recipient - set RCPT TO\n"
      . "  -c cc-recipient	- you can use multiple -c params\n"
      . "  -b bcc-recipient	- you can use multiple -b params\n"
      . "  -a auth_type: LOGIN, PLAIN\n"
      . "  -u username\n"
      . "  -p password\n"
      . "  -j subJect\n"
      . "  -m message body\n"
      . "  -n attachmeNt\n"
      . "  -d data file - use the given file to fill the whole DATA section of the smpt session\n"
      . "\n";

}

#
# Return an encoded string for PLAIN login
#
sub plain_string($$) {    #username password
    my ( $username, $password ) = @_;

    $username =~ s|@|\@|;    #escape @

    my $ret = encode_base64( "\000" . $username . "\000" . $password );
    chomp($ret);
    return ($ret);

}

#
# Handle PLAIN even without PERL SASL support
#
sub auth_smtp_plain($$$) {    #mailer username password
    my ( $smtp, $username, $password ) = @_;

    $smtp->datasend(
        "AUTH PLAIN " . plain_string( $username, $password ) . "\n" );
    $smtp->response();
}

#
# Handle LOGIN even without PERL SASL support
#
sub auth_smtp_login($$$) {    #mailer username password
    my ( $smtp, $username, $password ) = @_;

    $smtp->datasend("AUTH LOGIN\n");
    $smtp->response();

    $smtp->datasend( encode_base64($username) );
    $smtp->response();

    $smtp->datasend( encode_base64($password) );
    $smtp->response();

}

#
# Prepare Attachment body
#
sub datasend_attachment($$) {    #filename
    my ( $body, $path ) = @_;
    my $filename = $path;
    $filename =~ s|.*/||g;

    open( DATA, $path ) || die("Could not open the file:  $path");

    my $boundary = rand(1000000) . "antani" . rand(1000000);

    #
    # Attachment body is base64 encoded,
    #  has a mimetype and a boundary
    #
    my $mime_header =
        "Content-Transfer-Encoding: 7bit\n"
      . "Content-type: multipart/mixed; boundary=\"$boundary\"\n"
      . "MIME-Version: 1.0\n"
      . "This is a multi-part message in MIME format.\n" . "\n";

    #
    # Text part: body starts immediately after the Content-Type
    #   just one LF is needed
    #
    my $text_part =
        "\n\n--$boundary\n"
      . "Content-Transfer-Encoding: binary\n"
      . "Content-Type: text/plain\n" . "$body";

    #
    # Attachment part
    #  boundary starts with --$boundary and ends with --$boundary--
    #
    my $attachment_header =
        "\n\n--$boundary\n"
      . "Content-Transfer-Encoding: base64\n"
      . "Content-Type: application/*; name=\"$filename\"\n"
      . "Content-Disposition: attachment; filename=\"$filename\"\n" . "\n";

    my $attachment_body = "";
    my $buff;
    while ( read( DATA, $buff, 4096 ) ) {
        $attachment_body .= encode_base64($buff);
    }
    my $mime_footer = "--$boundary--\n";

    close(DATA);

    return
        $mime_header
      . $text_part
      . $attachment_header
      . $attachment_body
      . $mime_footer;

}

sub main() {
    my ( $argc, @argv ) = ( $#ARGV, @ARGV );

    my @notify = qw/NEVER/;
    my @cc     = ();
    my @bcc    = ();
    my $help;

    my ( $server, $port ) = qw/localhost 25/;
    my (
        $sender,       $recipient,   $cc,       $bcc,
        $auth_type,    $username,    $password, $subject,
        $message_body, $data_file,   $helo,     $data,
        $attachment,   $data_header, $iterations
    );

    my $result = GetOptions(
        's=s'      => \$server,         # server options
        'e|ehlo=s' => \$helo,
        'c|cc=s'   => \@cc,
        'b|bcc=s'  => \@bcc,
        'f=s'      => \$sender,
        't=s'      => \$recipient,
        'a=s'      => \$auth_type,      #authentication
        'u=s'      => \$username,
        'p=s'      => \$password,
        'd=s'      => \$data_file,      #body options
        'j=s'      => \$subject,
        'm=s'      => \$message_body,
        'n=s'      => \$attachment,
        'i=s'      => \$iterations,
        'v'        => \$verbose,
        'h|help'   => \$help            # help verbose
    );

    usage() if ( $help or $argc < 1 );

    if ($verbose) {
        @notify = qw/SUCCESS FAILURE DELAY/;
    }

    ( $server, $port ) = split( /:/, $server ) if ($server);

    #validate input parameters
    die("Missing SMTP host or port: use -s server:port")
      unless ( $server and $port );

    # sender and recipient are compulsory
    die("Missing sender or recipient") unless ( $sender and $recipient );

    #authentication requires:
    #	* -a PLAIN|LOGIN
    #	* user and password
    if ( defined $auth_type ) {
        die("Bad auth_type") unless ( ( $auth_type =~ m/PLAIN|LOGIN/ ) );
        die("Missing username or password") unless ( $username and $password );
    }

    # using a data file overrides the following fields:
    # 	* subject
    #	* message
    if ( defined $data_file ) {
        die("Missing file $data_file") unless ( -e $data_file );
        die("Data file overrides subject and message body")
          if ( $message_body or $subject );
        $data = `cat $data_file`;
    }
    else {
        die("Missing subject: use -j 'subject string'") unless ($subject);
        die(
"Missing body: use -m 'message body\n eventually spanning more lines.\n'"
        ) unless ($message_body);
        $data_header = sprintf( "Subject: %s\r\n", $subject );
        $data = $message_body;
    }

    #
    # Create the mailer class
    #
    my $mailer = Net::SMTP->new(
        $server,
        Port  => $port,
        Debug => $verbose
    ) or die("Can't create mailer object to $server:$port.");

    # eventually send helo
    $mailer->hello($helo) if ($helo);

    #
    # Eventually setup authentication. If you lack some perl modules like SASL
    #  use a local implementation of PLAIN login.
    #
    if ( defined $auth_type ) {
        dprint("setting authentication\n");
        if ( $auth_type eq "LOGIN" ) {
            auth_smtp_login( $mailer, $username, $password );
        }
        elsif ( $auth_type eq "PLAIN" ) {
            auth_smtp_plain( $mailer, $username, $password );
        }
        else {
            $mailer->auth( $username, $password );
        }
    }

    while ( $iterations-- > 0 ) {

        #
        # Now we can send mail
        #
        $mailer->mail($sender)
          or die("KO: rejected sender: $sender");
        $mailer->to($recipient)
          or die("KO: rejected recipient: $recipient");

        $mailer->bcc(@bcc) if ( @bcc > 0 );

        #
        # Set data header
        #
        if ( @cc > 0 ) {
            $mailer->cc(@cc);
            $data_header .= "CC: " . join( ',', @cc ) . "\r\n";
        }

        #
        # Eventually add one attachment, encapsulating data in a
        #  multipart message
        #
        $data = datasend_attachment( $data, $attachment )
          if ( defined $attachment );

        #
        # Finally add data
        #
        $mailer->data;

        # headers will never go into a mime message
        $mailer->datasend($data_header);

        # data may be embedded in a mime message
        $mailer->datasend($data);
        $mailer->dataend;

    }
    $mailer->quit;

    print "mail sent OK\n";
    exit(0);

}
&main();
