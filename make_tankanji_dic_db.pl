#!/usr/bin/perl
#require 5.008;
{ package main;
  my $TS = 'Time-stamp: <2016-02-09T04:02:57Z>';
  $TS =~ s/Time-stamp\:\s+<(.*)>/$1/;
  my $AUTHOR = "JRF (http://jrf.cocolog-nifty.com/)";
  our $VERSION = "0.03; make_tankanji_dic_dbm.pl; last modified at $TS; by $AUTHOR";
  our $DEBUG = 1;
}

use strict;
use warnings;
use utf8; # Japanese English

use Encode;
#use Encode::JIS2K;
use Unicode::Japanese;
use IO::Handle;
use Pod::Usage;
use Getopt::Long qw();

use Fcntl;
use SDBM_File;

our $ENCODING = "utf8";
our $JISX0213 = 0;
our $DBM_MODULE = "SDBM_File";
our $DBM_POSTFIX = ".sdb";
our @UNLINK_DBM_POSTFIX = (".sdb.dir", ".sdb.pag");

Getopt::Long::Configure("bundling", "auto_version", "no_ignore_case");
Getopt::Long::GetOptions
  (
   "s" => sub { $ENCODING = "cp932";},
   "e" => sub { $ENCODING = "euc-jp"; },
   "u" => sub { $ENCODING = "utf8"; },
   "jisx0213" => sub { $JISX0213 = 1; },
   "man" => sub {pod2usage(-verbose => 2)},
   "h|?" => sub {pod2usage(-verbose => 0, -output=>\*STDOUT, 
				-exitval => 1)},
   "help" => sub {pod2usage(1)},
  ) or pod2usage(-verbose => 0);

if (@ARGV != 1) {
  pod2usage(-verbose => 0);
}


MAIN:
{
  binmode(STDOUT, ":utf8");
  binmode(STDERR, ":utf8");

  my $DIC = $ARGV[0];

  open(my $ih, "<", $DIC) or die "$DIC: $!";

  if ($JISX0213 && $ENCODING eq "euc-jp") {
    $ENCODING = "euc-jisx0213";
    require Encode::JIS2K;
  }

  my $enc = Encode::find_encoding($ENCODING);

  if (-f ($DIC . $UNLINK_DBM_POSTFIX[0])) {
    foreach my $ext (@UNLINK_DBM_POSTFIX) {
      my $d = $DIC . $ext;
      unlink $d or die "$d: $!";
    }
  }
  my $dbm = $DIC . $DBM_POSTFIX;
  tie(my %dic, $DBM_MODULE, $dbm, O_RDWR | O_CREAT, 0666)
    or _die("Couldn't tie $DBM_MODULE to $dbm: $!");
  my $cur_yomi;
  my $cur_pos;
  my $tail = 0;
  while (1) {
    my $pos = tell $ih;
    my $s;
    my $last = ! ($s = <$ih>);
    $s = $enc->decode($s) if ! $last;
    if ($last || $s =~ /^\#\s*YOMI[ :]/) {
      my $new_yomi = ($last)? undef : $';
      if (defined $new_yomi) {
	$new_yomi =~ s/^\s+//s;
	$new_yomi =~ s/\s+$//s;
	$new_yomi = Unicode::Japanese->new($new_yomi)->hira2kata->z2h->sjis;
      }
      if (defined $cur_yomi) {
	my $size = $tail - $cur_pos;
	$dic{$cur_yomi} = pack("Vv", $cur_pos, $size);
#	print Encode::decode("cp932", $cur_yomi) . " $cur_pos $size\n";
      }
      last if $last;
      $cur_yomi = $new_yomi;
      $cur_pos = $pos;
      next;
    }
    next if $s =~ /^\#/;
    $s =~ s/\x0d?\x0a$//s;
    $s =~ s/\x1a$//s;
    next if $s eq "";
    $tail = tell $ih;
  }
  untie %dic;
  close($ih);
}

=pod

=head1	NAME

make_tankanji_dic_db.pl - prepares an SDBM_File of an Tankanji dictionary.

=head1	SYNOPSIS

B<make_tankanji_dic_db.pl> [-e|-s|-u] TEXT_FILE

=head1	Options

=over 8

=item B<--help>

shows help message about options.

=item B<--man>

shows man page.

=item B<--version>

shows version infomation.

=item B<-e>

specifies the encoding to euc-jisx0213.

=item B<-s>

specifies the encoding to cp932 (shift jis).

=item B<-u>

specifies the encoding to utf8.

=back

=head1	DESCRIPTION

B<This program> is distributed as a part of quail-naggy.el and used with
naggy-backend.pl.

=head1	AUTHORS

JRF E<lt>http://jrf.cocolog-nifty.com/softwareE<gt>

=head1	COPYRIGHT

Copyright 2015 by JRF L<http://jrf.cocolog-nifty.com/software/>

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

L<Encode>, L<naggy-backend.pl>

=cut

#Local Variables:
#time-stamp-format: "%04Y-%02m-%02dT%02H:%02M:%02SZ"
#time-stamp-time-zone: "UTC"
#time-stamp-start: "Time-stamp: [\"<]+"
#End:
