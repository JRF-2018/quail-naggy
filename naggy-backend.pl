#!/usr/bin/perl
#require 5.008_003;
{ package main;
  my $TS = 'Time-stamp: <2017-11-12T14:38:56Z>';
  $TS =~ s/Time-stamp\:\s+<(.*)>/$1/;
  my $AUTHOR = "JRF (http://jrf.cocolog-nifty.com/)";
  our $VERSION = "0.10; naggy-backend.pl; last modified at $TS; by $AUTHOR";
  our $DEBUG = 1;
}

## License:
##
##   The author is a Japanese.
##
##   I intended this program to be public-domain, but you can treat
##   this program under the (new) BSD-License or under the Artistic
##   License, if it is convenient for you.
##
##   Within three months after the release of this program, I
##   especially admit responsibility of efforts for rational requests
##   of correction to this program.
##
##   I often have bouts of schizophrenia, but I believe that my
##   intention is legitimately fulfilled.
##
## Author's Link:
##
##   http://jrf.cocolog-nifty.com/software/
##   (The page is written in Japanese.)
##

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package main;

  use FindBin;
  use File::Spec;
  use lib File::Spec->catdir($FindBin::Bin, 'lib');
}

{
  package Resource;

  use FindBin qw($Bin);
  use File::Spec::Functions qw(catfile catdir);
  use JRF::Resource;

  BEGIN {
    our @RESOURCE_PATH = (#".", "./trl", "./nginit",
			  catfile($ENV{HOME}, ".naggy-backend"),
			  $Bin,
			  catdir($Bin, "trl"),
			  catdir($Bin, "nginit"),
			  "/usr/share/emacs/site-lisp/quail-naggy", # Default.
			  "/usr/share/quail-naggy", # Alternative.
			 );

    our $USE_JISX0213 = 0;
    our $CONSOLE_ENCODING = "utf8";
    our $FILENAME_ENCODING = "utf8";
    our @KEYBOARD_PREF_ORDER = 
      qw(39 37 33 31 35 34 30 32 36 38
	 27 21 11  9 13 12  8 10 20 26
	 25  7  5  1  3  2  0  4  6 24
	 29 23 17 15 19 18 14 16 22 28);
  }
}


MAIN:
if (! defined $main::IN_TEST || ! $main::IN_TEST)
{
  use Naggy::Backend;
  my $ng = Naggy::Backend::Command->new(@ARGV);
  $ng->command_loop();
}


=pod

=head1	NAME

naggy-backend - the backend program for an input method "Naggy"; has a batch mode.

=head1	SYNOPSIS

B<naggy-backend> [--init-file INIT_FILE] [--translit TABLE_NAME] INPUT_FILE

=head1	Options

=over 8

=item B<--help>

shows help message about options.

=item B<--man>

shows man page.

=item B<--version>

shows version infomation.

=item B<--init-file> F<INIT_FILE>

specifies an initialization file.

=item B<--translit> F<TABLE_NAME>

runs the program as batch-mode to transliterate F<INPUT_FILE> by F<TABLE_NAME> loaded at F<INIT_FILE>.

=item B<-D>F<VAR>=F<VALUE>

=item B<--define> F<VAR>=F<VALUE>

set a variable in initialization.

=item B<--console-encoding> F<encoding>

specifies the encoding for console arguments.

=item B<--filename-encoding> F<encoding>

specifies the encoding for filenames.

=back

=head1	DESCRIPTION

B<This program> is the backend of Naggy input-method. But one can use its some functions as batch program.

=head1	AUTHORS

JRF E<lt>http://jrf.cocolog-nifty.com/softwareE<gt>

=head1	COPYRIGHT

Copyright 2015, 2017 by JRF L<http://jrf.cocolog-nifty.com/software/>

The author is a Japanese.

I intended this program to be public-domain, but you can treat
this program under the (new) BSD-License or under the Artistic
License, if it is convenient for you.

Within three months after the release of this program, I
especially admit responsibility of efforts for rational requests
of correction to this program.

I often have bouts of schizophrenia, but I believe that my
intention is legitimately fulfilled.

=head1	SEE ALSO

L<Encode>

=cut

#Local Variables:
#time-stamp-format: "%04Y-%02m-%02dT%02H:%02M:%02SZ"
#time-stamp-time-zone: "UTC"
#time-stamp-start: "Time-stamp: [\"<]+"
#End:
