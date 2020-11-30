#!/usr/bin/perl
#require 5.008;
{ package Naggy::Backend::Convert;
  our $VERSION = "0.17"; # Time-stamp: <2020-11-30T17:08:47Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Resource;
  our @KEYBOARD_PREF_ORDER;
  if (! @KEYBOARD_PREF_ORDER) {
    @KEYBOARD_PREF_ORDER = 
      qw(39 37 33 31 35 34 30 32 36 38
	 27 21 11  9 13 12  8 10 20 26
	 25  7  5  1  3  2  0  4  6 24
	 29 23 17 15 19 18 14 16 22 28);
  }
}

{
  package Naggy::Backend::Convert;
  use base qw(JRF::MyOO);

  use Naggy;

  __PACKAGE__->extend_template
    (
     ngb => undef,
     tankanji_dic => undef,
     skk_dics => [],
     table => {},
    );

  __PACKAGE__->extend_cvar
    (
     KEYBOARD_PREF_ORDER_INV => [],
    );

  sub new {
    my $class = shift;
    my $obj =  $class->SUPER::new();
    my ($ngb, %opt) = @_;

    $obj->{ngb} = $ngb;
    if (exists $opt{tankanji_dic}) {
      $obj->{tankanji_dic} = $opt{tankanji_dic};
    }
    if (exists $opt{skk_dics}) {
      @{$obj->{skk_dics}} = @{$opt{skk_dics}};
    }
    return $obj;
  }

  sub make_roman_filter {
    my $self = shift;
    my ($s) = @_;
    my $ngb = $self->{ngb};
    my @l;

    my $c = substr($s, 0, 1);
    $s = substr($s, 1);
    while ($s =~ /[A-Z]/) {
      push(@l, $c . $`);
      $c = $&;
      $s = $';
    }
    push(@l, $c . $s);
    return undef if @l <= 1;
    my $a = "";
    my $b = "";
    for (my $i = 0; $i < @l; $i++) {
      my $x = $ngb->{translit}->translit($ngb->{convert_translit}, $l[$i]);
      if ($i % 2) {
	$a = qr(${a}[^\x{3041}-\x{3096}]+);
	$b = qr($b\Q$x\E);
      } else {
	$a = qr($a\Q$x\E);
	$b = qr(${b}[^\x{3041}-\x{3096}]+);
      }
    }
    return qr(^(?:$a|$b)$);
  }

  sub japanese_convert {
    my $self = shift;
    my ($mode, $s) = @_;
    my $ngb = $self->{ngb};
    my $inv_table = $self->{cvar}->{KEYBOARD_PREF_ORDER_INV};
    my $use_roman_hint = exists $ngb->{INIT_VAR}->{JAPANESE_ROMAN_HINT}
      && Naggy::is_true($ngb->{INIT_VAR}->{JAPANESE_ROMAN_HINT});
    my $capitalized_tankanji = exists $ngb->{INIT_VAR}->{CAPITALIZED_TANKANJI}
      && $ngb->{INIT_VAR}->{CAPITALIZED_TANKANJI} eq "skk";

    my @l;
    while ($s =~ /:/) {
      push(@l, $`);
      $s = $';
    }
    push(@l, $s);
    my @r;
    while (@l) {
      my $c = shift(@l);
      if ($c eq "" && @l > 0 && $l[0] eq "") {
	push(@r, ":");
	shift(@l);
      } else {
	push(@r, $c);
      }
    }
    @l = @r;
    @r = ();
    while (@l) {
      my $c = shift(@l);
      my $d = "";
      if ($c ne "") {
	$d = $ngb->{translit}->translit($ngb->{convert_translit}, $c);
      }
      push(@r, [$c, $d]);
    }

    my ($c, @filter) = @r;
    my %r;
    @r = ();

    if ($c->[0] eq "" && @filter) {
      $c = shift(@filter);
      if ($mode eq "skk" && defined $self->{tankanji_dic}) {
	$mode = "tankanji";
      } else {
	$mode = "skk";
      }
    } elsif ($capitalized_tankanji
	     && $mode eq "tankanji" && $c ->[0] =~ s/^([A-Z\@])//) {
      $c->[0] = lc($1) . $c->[0];
      $mode = "skk";
    }

    if ($mode eq "skk") {
      foreach my $sdic (@{$self->{skk_dics}}) {
	my @l = $sdic->convert(@$c);
	foreach my $d (@l) {
	  if (exists $r{$d->[0]}) {
	    if (! defined $r[$r{$d->[0]}]->[3]) {
	      $r[$r{$d->[0]}]->[3] = $d->[1];
	    }
	  } else {
	    my $i = @r;
	    $i = int($i / 40) * 40 + $inv_table->[$i % 40];
	    push(@r, [$d->[0], $i, 0, $d->[1]]);
	    $r{$d->[0]} = @r - 1;
	  }
	}
      }
      if (defined $self->{tankanji_dic}) {
	my @l = $self->{tankanji_dic}->convert(@$c);
	foreach my $d (@l) {
	  if (! exists $r{$d->[0]}) {
	    my $i = @r;
	    $i = int($i / 40) * 40 + $inv_table->[$i % 40];
	    push(@r, [$d->[0], $i, 0, undef]);
	    $r{$d->[0]} = @r - 1;
	  }
	}
      }
    } else {
      my @l = $self->{tankanji_dic}->convert(@$c);
      foreach my $d (@l) {
	push(@r, [$d->[0], $d->[1], 0, undef]);
	if (! exists $r{$d->[0]}) {
	  $r{$d->[0]} = @r - 1;
	}
      }
    }

    my $rfilter;
    if ($use_roman_hint && $c->[0] =~ /[A-Z]/ && $c->[0] =~ /[a-z]/) {
      $rfilter = $self->make_roman_filter($c->[0]);
    }
    if (defined $rfilter) {
      for (my $i = 0; $i < @r; $i++) {
	if ($r[$i]->[0] =~ $rfilter) {
	  $r[$i]->[2] = 1;
	}
      }
    } else {
      if (@filter) {
	for (my $i = 0; $i < @r; $i++) {
	  $r[$i]->[2] = 1;
	}
      }
    }

    foreach my $c (@filter) {
      my %f;
      my $x = "";
      my $rfilter;
      if ($use_roman_hint && $c->[0] =~ /[A-Z]/ && $c->[0] =~ /[a-z]/) {
	$rfilter = $self->make_roman_filter($c->[0]);
      }
      foreach my $sdic (@{$self->{skk_dics}}, $self->{tankanji_dic}) {
	next if ! defined $sdic;
	my @l = $sdic->convert(@$c);
	if (defined $rfilter) {
	  foreach my $d (@l) {
	    if ($d->[0] =~ $rfilter) {
	      $x .= $d->[0];
	    }
	  }
	} else {
	  foreach my $d (@l) {
	    $x .= $d->[0];
	  }
	}
      }
      $x =~ s/[\x20-\x7e\x{3041}-\x{3093}\x{309b}\x{309c}\x{30a1}-\x{30F4}\x{30fc}]//sg;
      my $len = length($x);
      for (my $i = 0; $i < $len; $i++) {
	$f{substr($x, $i, 1)} = 1;
      }
      for (my $i = 0; $i < @r; $i++) {
	my $d = $r[$i]->[0];
	$d =~ s/[\x20-\x7e\x{3041}-\x{3093}\x{309b}\x{309c}\x{30a1}-\x{30F4}\x{30fc}]//sg;
	my $len = length($d);
	my $h = 0;
	for (my $i = 0; $i < $len; $i++) {
	  if (exists $f{substr($d, $i, 1)}) {
	    $h = 1;
	    last;
	  }
	}
	$r[$i]->[2] = $r[$i]->[2] * $h;
      }
    }

    @l = @r;
    @r = ();
    my @h;
    while (@l) {
      my $x = shift(@l);
      if ($x->[2]) {
	push(@h, $x);
      } else{
	push(@r, $x);
      }
    }
    return (@h, @r);
  }

  sub convert {
    my $self = shift;
    my ($s) = @_;
    my $ngb = $self->{ngb};
    my $use_modify = exists $ngb->{INIT_VAR}->{ALLOW_MODIFY_CONVERT}
      && Naggy::is_true($ngb->{INIT_VAR}->{ALLOW_MODIFY_CONVERT});
    my $mode_name;
    my $mode;
    if (exists $self->{ngb}->{INIT_VAR}->{DEFAULT_CONVERT}) {
      $mode_name = $ngb->{INIT_VAR}->{DEFAULT_CONVERT};
    }
    $mode_name = "tankanji" if ! defined $mode_name;
    if ($use_modify && $s =~ s/\#([^\#]+)$//) {
      $mode_name = $1;
    }
    if (exists $self->{table}->{$mode_name}) {
      $mode = $self->{table}->{$mode_name};
    } else {
      $ngb->rwarn("$mode_name: No coversion infomation.");
      return (undef);
    }
    if ($mode->[0] eq "convert" && $mode->[1] eq "tankanji"
	&& ! defined $self->{tankanji_dic}) {
      $mode = ["convert", "skk"];
    }

    if ($mode->[0] eq "convert") {
      if ($mode->[1] eq "unicode") {
	if (! $s =~ /^[01-9a-fA-F]+$/) {
	  $ngb->rwarn("$mode_name: Malformed Unicode.");
	  return (undef);
	}
	my $r = chr(hex($s));
	return ($r);
      } elsif ($mode->[1] eq "skk" || $mode->[1] eq "tankanji") {
	return $self->japanese_convert($mode->[1], $s);
      } else {
	die "Naggy::Backend::Convert: Unreacheable code!";
      }
    } elsif ($mode->[0] eq "translit") {
      my $r = $ngb->{translit}->translit($mode->[1], $s);
      if (! defined $r) {
	$ngb->rwarn("$mode->[1]: failed to translit.");
      }
      return ($r);
    } else {
      die "Naggy::Backend::Convert: Unreacheable code!";
    }
  }


 ClassInit:
  {
    my $inv_table = __PACKAGE__->get_cvar()->{KEYBOARD_PREF_ORDER_INV};
    for (my $i = 0; $i < 40; $i++) {
      $inv_table->[$Resource::KEYBOARD_PREF_ORDER[$i]] = $i
    }
  }
}

1;
