#!/usr/bin/perl
#require 5.008;
{ package Naggy::TankanjiDic;
  our $VERSION = "0.09"; # Time-stamp: <2017-07-06T20:40:37Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy::TankanjiDic;
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
     sjis_hack => 0,
    );

  sub new {
    my $class = shift;
    my $debug = $main::DEBUG;  # Why necessary?
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
      } elsif ($opt{encoding} =~ /cp932/i 
	       || $opt{encoding} =~ /shift[_ ]?jis/i) {
	$obj->{sjis_hack} = 1;
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
      if (! $self->{sjis_hack}) {
	$s = $self->{enc}->decode($s);
	my $l = 0;
	foreach my $s (split(/\x0a/, $s)) {
	  $s =~ s/\x0d$//s;
	  $s =~ s/\x1a$//s;
	  next if $s =~ /^\#/;
	  next if $s eq "";
	  my $x = 0;
	  my $len = length($s);
	  for (my $pos = 0; $x < 10 && $pos < $len; $pos++) {
	    if ($pos < $len - 1) {
	      my $c = substr($s, $pos, 2);
	      if ($c =~ /^[\x20-\x7e][\x20-\x7e]$/) {
		$pos++;
		$x++;
		next;
	      }
	    }
	    push(@r, [substr($s, $pos, 1), $l * 10 + $x]);
	    $x++;
	  }
	  $l++;
	}
      } else {
	my $l = 0;
	foreach my $s (split/\x0a/, $s) {
	  $s =~ s/\x0d$//s;
	  $s =~ s/\x1a$//s;
	  next if $s =~ /^\#/;
	  next if $s eq "";
	  my $x = 0;
	  while ($s ne "") {
	    my $f = ord(substr($s, 0, 1));
	    my $f2 = ord(substr($s, 1, 1));
	    my $c = substr($s, 0, 2);
	    $s = substr($s, 2);
	    if ($f <= 0x7e && $f >= 0x20) {
	      $x++;
	    } elsif ($f == 0x86 && $f2 >= 0xA2 && $f2 <= 0xED) {
	      $c = chr(0x2500 - 0xa2 + $f2);
	      push(@r, [$c, $l * 10 + $x]);
	      $x++;
	    } else {
	      $c = $self->{enc}->decode($c);
	      push(@r, [$c, $l * 10 + $x]);
	      $x++;
	    }
	  }
	  $l++;
	}
      }
    }
    @r = sort {my $sa = $a->[1];
	       $sa = int($sa / 40) * 40 + $Resource::KEYBOARD_PREF_ORDER[$sa % 40];
	       my $sb = $b->[1];
	       $sb = int($sb / 40) * 40 + $Resource::KEYBOARD_PREF_ORDER[$sb % 40];
	       $sa <=> $sb;
	     } @r;
    return @r;
  }

  sub _merge {
    my ($self) = shift;
    my (@l) = @_;
    my @m;
    my @r;

    while (@l) {
      my $x = shift(@l);
      my ($k, $pos) = @$x;
      while (defined $m[$pos] && $m[$pos] ne $k) {
	$pos += 40;
      }
      if (! defined $m[$pos]) {
	$m[$pos] = $k;
	push(@r, [$k, $pos]);
      }
    }
    return @r;
  }

  sub convert {
    my ($self) = shift;
    my ($orig, $yomi) = @_;
    my @r;
    if ($orig =~ /^[01-9A-Za-z]+$/) {
      my @r1 = $self->_raw_convert(Unicode::Japanese->new($yomi)
				   ->hira2kata->z2h->sjis);
      my @r2 = $self->_raw_convert($orig);
      if (@r1 && @r2) {
	@r = $self->_merge(@r1, @r2);
      } else {
	@r = (@r1, @r2);
      }
      return @r;
    } else {
      @r = $self->_raw_convert($orig);
      return @r if @r;
      @r = $self->_raw_convert(Unicode::Japanese->new($yomi)
				->hira2kata->z2h->sjis);
      return @r if @r;
      if ($yomi =~ tr/、。，．/，．、。/) {
	@r = $self->_raw_convert(Unicode::Japanese->new($yomi)
				 ->hira2kata->z2h->sjis);
	return @r if @r;
      }
      return ();
    }
  }
}

1;
