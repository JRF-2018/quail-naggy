#!/usr/bin/perl
#require 5.008;
{ package main;
  my $TS = 'Time-stamp: <2025-05-19T12:31:05Z>';
  $TS =~ s/Time-stamp\:\s+<(.*)>/$1/;
  my $AUTHOR = "JRF (http://jrf.cocolog-nifty.com/)";
  our $VERSION = "0.01; fix_skk_jisyo_l.pl; last modified at $TS; by $AUTHOR";
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

our $ENCODING = "euc-jp";
our $JISX0213 = 0;
our $OUTPUT = "SKK-JISYO.fixed.L";

Getopt::Long::Configure("bundling", "auto_version", "no_ignore_case");
Getopt::Long::GetOptions
  (
   "s" => sub { $ENCODING = "cp932";},
   "e" => sub { $ENCODING = "euc-jp"; },
   "u" => sub { $ENCODING = "utf8"; },
   "o=s" => \$OUTPUT,
   "jisx0213" => sub { $JISX0213 = 1; },
   "man" => sub {pod2usage(-verbose => 2)},
   "h|?" => sub {pod2usage(-verbose => 0, -output=>\*STDOUT, 
				-exitval => 1)},
   "help" => sub {pod2usage(1)},
  ) or usage(0);

if (@ARGV != 1) {
  usage(0);
}

sub usage {
  my ($ext) = @_;

  print STDERR <<"EOT";
Usage: $0 SKK-JISYO.L -o SKK-JISYO.fixed.L
make_skk_dic_db.pl -e SKK-JISYO.fixed.L
EOT

  exit($ext);
}

MAIN:
{
  binmode(STDOUT, ":utf8");
  binmode(STDERR, ":utf8");

  my $DIC = $ARGV[0];

  open(my $ih, "<", $DIC) or die "$DIC: $!";
  binmode($ih);
  open(my $oh, ">", $OUTPUT) or die "$OUTPUT: $!";
  binmode($oh);

  if ($JISX0213 && $ENCODING eq "euc-jp") {
    $ENCODING = "euc-jisx0213";
    require Encode::JIS2K;
  }

  my $enc = Encode::find_encoding($ENCODING);

  while (my $s = <$ih>) {
    $s = $enc->decode($s);
    $s =~ s/\n$//;
    if ($s =~ /^\s*;/s || $s =~ /^\s*$/s) {
      print $oh $enc->encode($s . "\n");
    } else {
      if ($s !~ / +/) {
	die "Parse Error: $s";
      }
      my $key = $`;
      my $sp = $&;
      my $rest = $';
      my @kouho = split(/\//, $rest);
      my @n = ();
      foreach my $k (@kouho) {
	my $c = $k;
	$c =~ s/;.*$//;
	if ($c ne "" && $c !~ /^[a-zA-Z\ ]+$/ && $c !~ /^[\x{3041}-\x{309F}\x{30A0}-\x{30FF}]+$/) {
	  push(@n, $k);
	}
      }
      @kouho = @n;
      if (@kouho) {
	my $pr = 0;
	foreach my $c (@kouho) {
	  my $k = $c;
	  $k =~ s/;.*$//;
	  if ($k =~ /[a-zA-Z]/) {
	    $pr = 1;
	  }
	  print STDERR $key . $sp . "/" . join("/", @kouho) . "/\n" if $pr;
	}
	print $oh $enc->encode($key . $sp . "/" . join("/", @kouho) . "/\n");
      }
    }
  }
  close($oh);
  close($ih);
}
