#!/usr/bin/perl
#require 5.008;
{ package Naggy::SKKDic;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:14:38Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy::SKKDic;
  use base qw(JRF::MyOO);

  use Encode qw();
#  use Encode::JIS2K;
  use Unicode::Japanese;

  use Fcntl;
  use SDBM_File;
  our $DBM_MODULE = "SDBM_File";
  our $DBM_EXT = ".sdb";

  __PACKAGE__->extend_template
    (
     filename => undef,
     fh => undef,
     hash => {},
     enc => Encode::find_encoding("utf8"),
    );

  our %KANA2OKURI 
    = (
       "あ" => "a",
       "い" => "i",
       "う" => "u",
       "え" => "e",
       "お" => "o",

       "か" => "k",
       "き" => "k",
       "く" => "k",
       "け" => "k",
       "こ" => "k",

       "さ" => "s",
       "し" => "s",
       "す" => "s",
       "せ" => "s",
       "そ" => "s",

       "た" => "t",
       "ち" => "t",
       "つ" => "t",
       "て" => "t",
       "と" => "t",

       "な" => "n",
       "に" => "n",
       "ぬ" => "n",
       "ね" => "n",
       "の" => "n",

       "は" => "h",
       "ひ" => "h",
       "ふ" => "h",
       "へ" => "h",
       "ほ" => "h",

       "ま" => "m",
       "み" => "m",
       "む" => "m",
       "め" => "m",
       "も" => "m",

       "や" => "y",
       "ゆ" => "y",
       "よ" => "y",

       "ら" => "r",
       "り" => "r",
       "る" => "r",
       "れ" => "r",
       "ろ" => "r",

       "わ" => "w",
       "ゐ" => "w",
       "ゑ" => "w",
       "を" => "w",

       "が" => "g",
       "ぎ" => "g",
       "ぐ" => "g",
       "げ" => "g",
       "ご" => "g",

       "ざ" => "z",
       "じ" => "z",
       "ず" => "z",
       "ぜ" => "z",
       "ぞ" => "z",

       "だ" => "d",
       "ぢ" => "d",
       "づ" => "d",
       "で" => "d",
       "ど" => "d",

       "ば" => "b",
       "び" => "b",
       "ぶ" => "b",
       "べ" => "b",
       "ぼ" => "b",

       "ぱ" => "p",
       "ぴ" => "p",
       "ぷ" => "p",
       "ぺ" => "p",
       "ぽ" => "p",

       "う゛" => "v",
      );

  sub new {
    my $class = shift;
    my $debug = $main::DEBUG; # Why necessary?
    			      # JRF::MyOO can do something wrong.
    $main::DEBUG = 0;
    my $obj =  $class->SUPER::new(@_);
    $main::DEBUG = $debug;
    my $filename;
    if (@_ % 2) {
      $filename = shift;
    }
    my %opt = @_;
    if (exists $opt{file}) {
      $filename = $opt{file};
    }
    die "No filename is specified." if ! defined $filename;
    $obj->{filename} = $filename;
    if (exists $opt{encoding}) {
      if ($opt{encoding} =~ /jisx0213/i) {
	require Encode::JIS2K;
      }
      $obj->{enc} = Encode::find_encoding($opt{encoding});
      die "$opt{encoding}: Invaild encoding." if ! defined $obj->{enc};
    }
    open($obj->{fh}, "<", $filename) or die "$filename: $!";
    binmode($obj->{fh});
    my $dbm = $filename . $DBM_EXT;
    tie(%{$obj->{hash}}, $DBM_MODULE, $dbm, O_RDONLY, 0666)
      or _die("Couldn't tie $DBM_MODULE to $dbm: $!");
    return $obj;
  }

  sub DESTROY {
    my $self = shift;
    close $self->{fh} if defined $self->{fh};
    my $x = tied %{$self->{hash}};
    if (defined $x) {
      undef $x;
      untie %{$self->{hash}};
    }
  }

  sub _raw_convert {
    my ($self) = shift;
    my ($key) = @_;
    my @r;
    if (exists $self->{hash}->{$key}) {
      my ($pos, $size) = unpack("Vv", $self->{hash}->{$key});
      seek($self->{fh}, $pos, 0);
      read($self->{fh}, my $s, $size) or die "$self->{filename}: $!";
      $s = $self->{enc}->decode($s);
      $s =~ s/^\s+//s;
      $s =~ s/\s+$//s;
      (undef, $s) = split(/\s+/, $s, 2);
      foreach my $c (split(/\//, $s)) {
	next if $c eq "";
	my ($d, $com) = split(/\;/, $c);
	next if $d eq "";
	push(@r, [$d, $com]);
      }
    }
    return @r;
  }

  sub convert {
    my ($self) = shift;
    my ($orig, $yomi) = @_;
    my @r;
    push(@r, $self->_raw_convert($orig));
    push(@r, $self->_raw_convert(Unicode::Japanese->new($yomi)
				 ->hira2kata->z2h->sjis));

    for (my $pos = length($yomi) - 1; $pos > 0; $pos--) {
      my $o = substr($yomi, $pos, 1);
      my $pre = substr($yomi, 0, $pos);
      my $post = substr($yomi, $pos);
      if (($o eq "゛" || $o eq "゜") && $pos > 2) {
	my $o2 = substr($yomi, $pos - 1, 2);
	if (exists $KANA2OKURI{$o2}) {
	  $pos--;
	  $o = $o2;
	  $pre = substr($yomi, 0, $pos);
	  $post = substr($yomi, $pos);
	}
      } elsif ($o eq "っ" && $pos < length($yomi) - 1) {
	my $o2 = substr($yomi, $pos + 1, 1);
	if (exists $KANA2OKURI{$o2} && $KANA2OKURI{$o2} !~ /^[aiueo]$/) {
	  $o = $o2;
	}
      }
      if (exists $KANA2OKURI{$o}) {
	my $key = Unicode::Japanese->new($pre . $KANA2OKURI{$o})->hira2kata->z2h->sjis;
	my @l = $self->_raw_convert($key);
	for (my $i = 0; $i < @l; $i++) {
	  $l[$i] = [$l[$i]->[0] . $post, $l[$i]->[1]];
	}
	push(@r, @l);
      }
    }
    return @r;
  }
}

1;
