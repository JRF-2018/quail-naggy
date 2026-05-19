#!/usr/bin/perl
#require 5.008;
{ package Naggy;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:15:14Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy;
  use base qw(Exporter);

  our @EXPORT_OK = qw(escape_string unescape_string regular_string
		      is_true next_line);

  sub escape_string {
    my ($src) = @_;
    return undef if ! defined $src;
    return "\\0" if $src eq "";
    $src =~ s([\x00-\x20\x7F\\\#]){
      sprintf("\\x%02X", ord($&));
    }gsex;
    return $src;
  }

  sub unescape_string {
    my ($src) = @_;
    return undef if ! defined $src;
    $src =~ s(\\([0nt]|[^01-9A-Za-z]|x[01-9a-fA-F][01-9a-fA-F]|u\{[01-9a-fA-F]+\}|u\([01-9a-fA-F]+\))){
      if ($1 eq "0") {
	"";
      } elsif (substr($&, 1, 1) eq "x") {
	chr(hex(substr($&, 2)));
      } elsif (substr($&, 1, 1) eq "u") {
	chr(hex(substr($&, 3, -1)));
      } elsif ($1 eq "n") {
	"\n";
      } elsif ($1 eq "t") {
	"\t";
      } else {
	$1;
      }
    }gsex;
    return $src;
  }

  sub regular_string {
    my ($src) = @_;
    $src =~ s/\\\\/\\u\{5C\}/gs;
    $src =~ s(\\([^01-9A-Za-z])){sprintf("\\u{%X}", ord($1))}gsex;
    return $src;
  }

  sub is_true {
    my ($s) = @_;
    return defined $s && $s ne "" && $s !~ /^(?:false|0+)$/si;
  }

  sub next_line {
    my ($l) = @_;
    my $r;
    my $done = 0;
    my $comment_only = 1;
    while (! $done && @$l) {
      my $s = shift(@$l);
      $s =~ s/\x0a$//s;
      $s =~ s/\x0d$//s;
      $s = Naggy::regular_string($s);
      my $read_next = ($s =~ s/\\$//);
      if (! ($s =~ s/\#.*$// && $s =~ /^\s*$/)) {
	$comment_only = 0;
      }
      $done = ! ($read_next || $comment_only);
      if (defined $r) {
	$r .= $s;
      } else {
	$r = $s;
      }
    }
    return $r;
  }
}

1;
