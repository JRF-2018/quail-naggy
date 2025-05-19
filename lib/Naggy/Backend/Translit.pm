#!/usr/bin/perl
#require 5.008;
{ package Naggy::Backend::Translit;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:15:47Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy::Backend::Translit;
  use base qw(JRF::MyOO);

  use Encode qw();
  use Naggy::Translit;

  __PACKAGE__->extend_template
    (
     table => {},
    );

  our %TRANSLIT_TABLE
    = (
       # abbrevs.
       # hw:	half width.
       # fw:	full width.
       # kata:	japanese katakana (default fw)
       # hira:	japanese hiragana (fw)
       # alpha:	ascii alphabets and some symbols (default hw)
       identical => [],
      );

  sub new {
    my $class = shift;
    my $obj =  $class->SUPER::new(@_);
    my %opt = @_;
    %{$obj->{table}} = %TRANSLIT_TABLE;
    return $obj;
  }

  sub translit {
    my $self = shift;
    my ($spec, $s) = @_;
    my $tbl = $self->{table};

    sub _naggy_translit {
      my ($tbl, $spec, $s, $visited) = @_;
      return undef if ! defined $s;
      return undef if exists $visited->{$spec};
      $visited->{$spec} = 1;

      if (ref $spec eq 'ARRAY') {
	foreach my $t (@{$spec}) {
	  $s = _naggy_translit($tbl, $t, $s, $visited);
	}
	return $s;
      } elsif (ref($spec)) {
	return $spec->translit($s);
      } else {
	foreach my $t (split(/\s+/, $spec)) {
	  return undef if ! exists $tbl->{$t};
	  $s = _naggy_translit($tbl, $tbl->{$t}, $s, $visited);
	}
	return $s;
      }
    }
    return _naggy_translit($tbl, $spec, $s, {});
  }

  sub rename {
    my $self = shift;
    my ($from, $to) = @_;
    my $tbl = $self->{table};

    return 0 if ! exists $tbl->{$from};

    sub _rename_in_string {
      my ($from, $to, $s) = @_;
      return join(" ", map {($_ eq $from)? $to : $_} split(/\s+/, $s));
    }

    sub _rename_in_array {
      my ($from, $to, @l) = @_;
      return map {
	if (ref($_) eq 'HASH') {
	  return $_;
	} elsif (ref($_) eq 'ARRAY') {
	  return [_rename_in_array($from, $to, @{$_})];
	} else {
	  return _rename_in_string($from, $to, $_);
	}
      } @l;
    }

    foreach my $key (keys %$tbl) {
      my $spec = $tbl->{$key};
      if (ref($spec) eq 'ARRAY') {
	$tbl->{$key} = [_rename_in_array($from, $to, @{$spec})];
      } elsif (ref($spec)) {
	# do none;
      } else {
	$tbl->{$key} = _rename_in_string($from, $to, $spec);
      }
    }

    $tbl->{$to} = $tbl->{$from};
    delete $tbl->{$from};
  }

  sub alpha_charmap {
    my $self = shift;
    my ($spec) = @_;
    my $tbl = $self->{table};

    sub _naggy_alpha_charmap {
      my ($tbl, $spec, $charmap, $visited) = @_;
      return undef if ! defined $charmap;
      return undef if exists $visited->{$spec};
      $visited->{$spec} = 1;

      if (ref($spec) && (ref $spec)->isa("Naggy::Translit")) {
	foreach my $key (keys %{$charmap}) {
	  $charmap->{$key} = $spec->translit($charmap->{$key});
	}
	$spec->load_now() if ! $spec->{is_loaded};
	foreach my $key (keys %{$spec->{table}}) {
	  next if $key !~ /^[\x21-\x7E]+$/;
	  next if exists $charmap->{$key};
	  my $ideo = $spec->{table}->{$key};
	  $ideo = $spec->{ideo}->{$key} if exists $spec->{ideo}->{$key};
	  $charmap->{$key} = $ideo;
	}
	return $charmap;
      } elsif (ref($spec) eq 'ARRAY') {
	foreach my $t (@{$spec}) {
	  $charmap = _naggy_alpha_charmap($tbl, $t, $charmap, $visited);
	  return undef if ! defined $charmap;
	}
	return $charmap;
      } else {
	foreach my $t (split(/\s+/, $spec)) {
	  return undef if ! exists $tbl->{$t};
	  $charmap = _naggy_alpha_charmap($tbl, $tbl->{$t}, $charmap, $visited);
	  return undef if ! defined $charmap;
	}
	return $charmap;
      }
    }

    return _naggy_alpha_charmap($tbl, $spec, {}, {});
  }

  sub completion_beginning {
    my $self = shift;
    my ($spec) = @_;
    my $tbl = $self->{table};

    sub _completion_beginning {
      my ($tbl, $spec, $re, $visited) = @_;
      return undef if exists $visited->{$spec};
      $visited->{$spec} = 1;

      if (ref($spec) eq 'ARRAY') {
	foreach my $t (@{$spec}) {
	  $re = _completion_beginning($tbl, $t, $re, $visited);
	}
	return $re;
      } elsif (ref($spec)) {
	$spec->load_now() if ! $spec->{is_loaded};

	my $tmp = $spec->{completion_beginning};
	if (defined $tmp) {
	  if (defined $re) {
	    return qr/$re|$tmp/;
	  } else {
	    return $tmp;
	  }
	} else {
	  return $re;
	}
      } else {
	foreach my $t (split(/\s+/, $spec)) {
	  return undef if ! exists $tbl->{$t};
	  $re = _completion_beginning($tbl, $tbl->{$t}, $re, $visited);
	}
	return $re;
      }
    }

    return _completion_beginning($tbl, $spec, undef, {});
  }

  sub complete {
    my $self = shift;
    my ($spec, $s) = @_;

    my $compbeg = $self->completion_beginning($spec);
    my $charmap = $self->alpha_charmap($spec);

    return undef if ! defined $charmap;

    my $prefix = "";

    if (defined $compbeg) {
      my $match = undef;
      while ($s =~ $compbeg) {
	$prefix .= $match if defined $match;
	$prefix .= $`;
	$match = $&;
	$s = $';
      }
      if (defined $match) {
	$s = $match . $s;
      }
    }

    my $r = {};
    my $compl = undef;
    my $ex = undef;
    foreach my $k (keys %{$charmap}) {
      if (uc(substr($k, 0, length($s))) eq uc($s)) {
	$r->{$k} = $charmap->{$k};

	if (uc($k) eq uc($s)) {
	  if (! defined $ex || $k eq $s) {
	    $ex = $k;
	  }
	  next;
	}
	if (! defined $compl) {
	  $compl = $s . substr($k, length($s));
	} else {
	  next if length($compl) <= length($s);
	  $compl = substr($compl, 0, length($k))
	    if length($k) < length($compl);
	  for (my $l = length($s) + 1;
	       length($compl) >= $l && length($k) >= $l; $l++) {
	    if (uc(substr($k, 0, $l)) ne uc(substr($compl, 0, $l))) {
	      $compl = substr($compl, 0, $l - 1);
	      last;
	    }
	  }
	}
      }
    }
    $compl = $ex if defined $ex && ! defined $compl;
    %{$r} = %{$charmap} if ! %{$r};

    return {prefix => $prefix, word => $s, completion => $compl, map => $r};
  }

 ClassInit:
  {
    use Unicode::Japanese;
    my $fn;

    sub fw2hw {
      return Unicode::Japanese->new($_[0])->z2h->getu;
    }

    sub hw2fw {
      return Unicode::Japanese->new($_[0])->h2z->getu;
    }
    sub hwkata2kata {
      my ($s) = @_;
      $s =~ s([\x{FF61}-\x{FF9F}]+){
	Unicode::Japanese->new($&)->h2z->getu;
      }gsex;
      return $s;
    }
    sub kata2hwkata {
      my ($s) = @_;
      $s =~ s([\x{3001}-\x{301C}\x{3099}-\x{309e}\x{30a1}-\x{30fe}]+){
	Unicode::Japanese->new($&)->z2h->getu;
      }gsex;
      return $s;
    }
    sub hira2kata {
      return Unicode::Japanese->new($_[0])->hira2kata->getu;
    }

    sub kata2hira {
      return Unicode::Japanese->new($_[0])->kata2hira->getu;
    }

    $TRANSLIT_TABLE{"hw-fw"} = Naggy::Translit::Function->new(\&hw2fw);
    $TRANSLIT_TABLE{"hwkata-kata"} = Naggy::Translit::Function->new(\&hwkata2kata);
    $TRANSLIT_TABLE{"fw-hw"} = Naggy::Translit::Function->new(\&fw2hw);
    $TRANSLIT_TABLE{"kata-hwkata"} = Naggy::Translit::Function->new(\&kata2hwkata);
    $TRANSLIT_TABLE{"hira-kata"} = Naggy::Translit::Function->new(\&hira2kata);
    $TRANSLIT_TABLE{"kata-hira"} = Naggy::Translit::Function->new(\&kata2hira);
    sub simplify_hebrew {
      my ($s) = @_;
      $s =~ s/[\x{591}-\x{5BB}\x{5BD}-\x{5C2}\x{5C4}-\x{5C7}]//g;
      $s =~ s/\x{5F0}/\x{5D5}\x{5D5}/g;
      $s =~ s/\x{5F1}/\x{5D5}\x{5D9}/g;
      $s =~ s/\x{5F2}/\x{5D9}\x{5D9}/g;
      return $s;
    }
    $TRANSLIT_TABLE{"hebrew-simplest_hebrew"}
      = Naggy::Translit::Function->new(\&simplify_hebrew);
  }
}

1;
