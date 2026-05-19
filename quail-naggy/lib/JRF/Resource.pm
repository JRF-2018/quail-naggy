#!/usr/bin/perl
#require 5.008;
{ package JRF::Resource;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:16:28Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package main;
  our $DEBUG;
  $DEBUG = 0 if ! defined $DEBUG;
}

{
  package JRF::Resource;
  use base qw(Exporter);
  our @EXPORT = qw(locate_file_resource);
  no strict; no warnings;
  *{locate_file_resource} = \&Resource::locate_file_resource;
}

{
  package Resource;
#  use GD::simple;
  use File::Spec::Functions qw(catfile file_name_is_absolute rel2abs
			       splitpath splitdir no_upwards);
  use JRF::Utils qw(encode_fn);


  our @RESOURCE_PATH;
  our $CONSOLE_ENCODING;
  $CONSOLE_ENCODING = "utf8" if ! defined $CONSOLE_ENCODING;
  our $FILENAME_ENCODING;
  $FILENAME_ENCODING = "utf8" if ! defined $FILENAME_ENCODING;
#  our %COLOR_NAME_LC;

  sub is_subpath {
    my ($a, $b, $child_only) = @_;
    my ($av, $ad) = splitpath($a, 1);
    my ($bv, $bd) = splitpath($b, 1);
    my @ad = ($av, splitdir($ad));
    my @bd = ($bv, splitdir($bd));
    return 0 if defined $child_only && $child_only && @ad != @bd + 1;
    for (my $i = 0; $i < @bd; $i++) {
      return 0 if $i >= @ad || $bd[$i] ne $ad[$i];
    }
    return 1;
  }

  sub is_last_path {
    my ($a, $b) = @_;
    return 0 if ! (length($b) >= length($a) && substr($b, -length($a)) eq $a);
    my ($av, $ad) = splitpath($a, 1);
    my ($bv, $bd) = splitpath($b, 1);
    return 0 if $av ne ""  && $av ne $bv;
    my @ad = reverse splitdir($ad);
    my @bd = reverse splitdir($bd);
    for  (my $i = 0; $i < @ad; $i++) {
      return 0 if $i >= @bd || $ad[$i] ne $bd[$i];
    }
    return 1;
  }

  sub locate_file_resource {
    my ($f) = @_;

    return undef if ! defined $f || $f eq "";
    my ($v, $d, $b) = splitpath($f);
    if (defined $d && ! file_name_is_absolute($f)) {
      my @d = splitdir($d);
      return undef if no_upwards(@d) != @d;
    }

    foreach my $d (@Resource::RESOURCE_PATH) {
      my $p;
      if (file_name_is_absolute($f)) {
	if ($d eq "") {
	  $p = $f;
	} elsif (is_subpath($f, rel2abs($d))) {
	  $p = $f;
	}
      } else {
	if (is_last_path($f, $d)) {
	  $p = rel2abs($d);
	} elsif ($d ne "") {
	  $p = rel2abs(catfile($d, $f));
	}
      }
      if (defined $p) {
	my $e = encode_fn($p);
	return $p if -f $e || -d $e;
      }
    }
    return undef;
  }

 ModuleInit:
  {
    binmode(STDOUT, ":encoding($Resource::CONSOLE_ENCODING)") if $main::DEBUG;
    binmode(STDERR, ":encoding($Resource::CONSOLE_ENCODING)");

#    my $cn = GD::Simple->color_names();
#    foreach my $k (keys %$cn) {
#      my $v = $cn->{$k};
#      $COLOR_NAME_LC{lc($k)} = $v;
#    }
  }
}

1;
