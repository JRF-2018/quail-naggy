#!/usr/bin/perl
#require 5.008;
{ package JRF::Utils;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:16:45Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package JRF::Utils;
  use base qw(Exporter);

  use Encode qw();
  use Carp;
  use JRF::Resource;

  our @EXPORT_OK = qw(encode_con decode_con encode_fn decode_fn
		      encode_u decode_u parse_int unpack_bits pack_bits
		      xd dump);
  our %EXPORT_TAGS = (all => \@EXPORT_OK, debug => [qw(xd dump)]);

  sub encode_con {
    my ($s) = @_;
    return Encode::encode($Resource::CONSOLE_ENCODING, $s,
			  sub { sprintf "\\u{%X}", $_[0] });
  }

  sub decode_con {
    my ($s) = @_;
    return Encode::decode($Resource::CONSOLE_ENCODING, $s,
			  sub { sprintf "\\u{%X}", $_[0] });
  }

  sub encode_fn {
    my ($s) = @_;
    return Encode::encode($Resource::FILENAME_ENCODING, $s,
			  sub { sprintf "\\u{%X}", $_[0] });
  }

  sub decode_fn {
    my ($s) = @_;
    return Encode::decode($Resource::FILENAME_ENCODING, $s,
			  sub { sprintf "\\u{%X}", $_[0] });
  }

  sub encode_u {
    my ($s) = @_;
    return Encode::encode("utf8", $s,
			  sub { sprintf "\\u{%X}", $_[0] });
  }

  sub decode_u {
    my ($s) = @_;
    return Encode::decode("utf8", $s,
			  sub { sprintf "\\u{%X}", $_[0] });
  }

  sub unpack_bits {
    my ($origspec, $origbits) = @_;
    my @r;
    my $c = "B";
    my $len = 0;
    my $spec = reverse($origspec);
    my $bits = $origbits;
    while ($spec ne "") {
      my $n = 1;
      if ($spec =~ s/^[01-9]+//) {
	$n = reverse($&);
      }
      $spec =~ s/^.//;
      if ($& eq "b") {
	$c = "b";
      }
      push(@r, $bits & ((1 << $n) - 1));
      $bits = $bits >> $n;
      $len += $n;
    }
    if ($c ne "b") {
      return reverse @r;
    }
    @r = ();
    $spec = $origspec;
    $bits = $origbits;
    while ($spec ne "") {
      my $n = 1;
      my $c = "B";
      if ($spec =~ s/^[^01-9]//) {
	$c = $&;
      }
      if ($spec =~ s/^[01-9]+//) {
	$n = $&;
      }
      if ($c eq "b") {
	push(@r, $bits & ((1 << $n) - 1));
	$bits = $bits >> $n;
      } else {
	push(@r, ($bits >> ($len - $n)) & ((1 << $n) - 1));
      }
      $len -= $n;
    }
    return @r;
  }

  sub pack_bits {
    my ($spec, @bits) = @_;
    my @r;
    my $len = 0;
    my $bits = 0;
    while (@bits) {
      my $b = shift(@bits);
      my $n = 1;
      my $c = "B";
      if ($spec =~ s/^[^01-9]//) {
	$c = $&;
      }
      if ($spec =~ s/^[01-9]+//) {
	$n = $&;
      }
      $b = $b & ((1 << $n) - 1);
      if ($c eq "b") {
	$bits = $bits | ($b << $len);
      } else {
	$bits = ($bits << $n) | $b;
      }
      $len += $n;
    }
    return $bits;
  }

  sub parse_int {
    my ($s, $radix) = @_; # $radix is a preferred radix, not forced.
    $s =~ s/^\s+//s;
    my $neg = ($s =~ s/^\-\s*//)? -1 : 1;
    if ($s =~ /^0x([01-9A-F_]+)/i || $s =~ /^0x\{([01-9A-F_]+)\}/i || $s =~ /^0x\(([01-9A-F_]+)\)/i) {
      my $x = $1 || "0";
      $x =~ s/_//g;
      return $neg * hex($x);
    } elsif ($s =~ /^0o([01-7_]+)/i) {
      my $x = $1;
      $x =~ s/_//g;
      return $neg * oct($x);
    } elsif (defined $radix && $radix != 16 && $s =~ /^0d([01-9_]+)/i) {
      my $x = $1 || "0";
      $x =~ s/_//g;
      return $neg * int($x);
    } elsif (defined $radix && $radix != 16 && $s =~ /^0b([01_]+)/i) {
      my $x = $1 || "0";
      $x =~ s/_//g;
      return $neg * ord(pack("b" . length($x), scalar reverse($x)));
    } elsif ($s =~ /^0o\{([01-7_]+)\}/i || $s =~ /^0o\(([01-7_]+)\)/i) {
      my $x = $1 || "0";
      $x =~ s/_//g;
      return $neg * oct($x);
    } elsif ($s =~ /^0d\{([01-9_]+)\}/i || $s =~ /^0d\(([01-9_]+)\)/i) {
      my $x = $1 || "0";
      $x =~ s/_//g;
      return $neg * int($x);
    } elsif ($s =~ /^0b\{([01_]+)\}/i || $s =~ /^0b\(([01_]+)\)/i) {
      my $x = $1 || "0";
      $x =~ s/_//g;
      return $neg * ord(pack("b" . length($x), scalar reverse($x)));
    } elsif (! defined $radix || ! $radix || $radix == 10) {
      $s =~ s/_//g;
      $s = $s || "0";
      return $neg * int($s);
    }
    if ($radix == 16) {
      $s =~ s/_//g;
      $s = $s || "0";
      return $neg * hex($s);
    } elsif ($radix == 8) {
      $s =~ s/_//g;
      $s = $s || "0";
      return $neg * oct($s);
    } elsif ($radix == 2) {
      $s =~ s/_//g;
      $s = $s || "0";
      $s =~ /^([01]+)/;
      return $neg * ord(pack("b" . length($1), scalar reverse($1)));
    } else {
      carp (__PACKAGE__ . "::parse_int : supports radix of 2, 8, 10 and 16 only, not $radix.");
      return undef;
    }
  }

  sub dump {
    use Data::Dumper;
    print Dumper(@_);
  }

  sub xd {
    my @r;
    foreach my $s (@_) {
      push(@r, join(" ", map {scalar unpack("H2", $_)} split("", $s)));
    }
    if (wantarray()) {
      return @r;
    } else {
      return join(" ", @r);
    }
  }
}

1;
