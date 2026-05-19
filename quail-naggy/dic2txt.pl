#!/usr/bin/perl

use utf8;
use strict;
use warnings;

use Fcntl qw(:seek);

our $KAZE_REA = "c:/WINDOWS/Wind2.rea";
our $KAZE_DIC = "c:/WINDOWS/Wind2.dic";
#our $KAZE_REA = "c:/ProgramData/Wind2/Wind2.rea";
#our $KAZE_DIC = "c:/ProgramData/Wind2/Wind2.dic";
#our $KA_TXT = "ka.txt";
our $KA_TXT;
our $UNDEF_CODE = "  ";

sub usage {
  print STDERR "usage: dic2txt REA DIC [TXT]\n";
  exit(1);
}

our @KAZE_ORDER = (
    40,  38,  32,  34,  36,  35,  33,  31,  37,  39,
    22,  16,   6,  10,  14,  13,   9,   5,  15,  21,
    18,  12,   2,   4,   8,   7,   3,   1,  11,  17,
    30,  28,  20,  24,  26,  25,  23,  19,  27,  29,
);
our %POSTOWIN = ();
for (my $i = 0; $i < 40; $i++) {
  $POSTOWIN{$KAZE_ORDER[$i] - 1} = $i;
}

&usage() if @ARGV < 2;
$KAZE_REA = shift @ARGV;
$KAZE_DIC = shift @ARGV;
$KA_TXT = shift @ARGV if @ARGV;

&dump_kaze($KAZE_REA, $KAZE_DIC, $KA_TXT);

exit(0);

sub postowin {
  my ($pos) = @_;
  my ($page, $loc);
  $pos--;
  $loc = $POSTOWIN{$pos % 40};
  $page = int($pos /= 40);
  return ($page, $loc);
}

sub dump_kaze {
  my ($rea, $dic, $txt) = @_;
  my ($pre_size) = 0x50;
  my ($buf);
  open(REA, $rea) or die;
  binmode(REA);
  open(DIC, $dic) or die;
  binmode(DIC);
  if (defined $txt) {
    open(TXT, ">$txt") or die;
    binmode(TXT);
  } else {
    open(TXT, ">&STDOUT") or die;
  }
  binmode(TXT);

  seek(REA, $pre_size, SEEK_SET) or die;
  read(REA, $buf, 2 * 4) or die;
  my ($num, $cache, $unknown1, $unknown2) = unpack("S*", $buf);
  seek(REA, $cache * 8 + $unknown1 * 8 + 0x10, SEEK_CUR);
  my ($yomi, $dicaddr, $bytes, $pos, $subpos, $kanji);
  my (@page, $page, $loc, @p);
  while ($num > 0) {
    $num--;
    read(REA, $buf, 12);
    ($yomi, $dicaddr, $bytes) = unpack("a8SS", $buf);
    $yomi =~ s/\x00+//;
    seek(DIC, $pre_size + $dicaddr, SEEK_SET);
    read(DIC, $buf, $bytes);
    while (length($buf) > 0) {
      ($pos, $buf) = unpack("Ca*", $buf);
      if ($pos == 0xFF) {
	($subpos, $buf) = unpack("Ca*", $buf);
	if ($subpos >= 0x81) {
	  $buf = pack("C", $subpos) . $buf;
	} else {
	  $pos += $subpos;
	}
      }
      ($kanji, $buf) = unpack("a2a*", $buf);
      ($page, $loc) = &postowin($pos);
      $page[$page * 40 + $loc] = $kanji;
    }
    print TXT "#YOMI:$yomi\n";
    while (@page) {
      @p = splice(@page, 0, 40);
      $p[39] = undef if @p < 40;
      foreach my $c (@p) {
	$c = $UNDEF_CODE if ! defined $c;
      }
      while (@p) {
	print TXT join("", splice(@p, 0, 10)) . "\n";
      }
      print TXT "#\n";
    }
  }
  close(DIC);
  close(REA);
  close(TXT);
}
