#!/usr/bin/perl
#require 5.008;
{ package JRF::Utils::HashFreezer;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:16:11Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package JRF::Utils::HashFreezer;
  use Tie::Hash;
  use Carp;
  use base qw(Tie::ExtraHash);

  sub TIEHASH {
    my $class = shift;
    return (bless [{}, {@_}], $class);
  }

  sub STORE {
    if (! exists $_[0][1]->{template}->{$_[1]}) {
      carp "The key '$_[1]' doesn't exist in the hash.\n";
    }
    $_[0][0]{$_[1]} = $_[2];
  }

  sub FETCH {
    if (! exists $_[0][1]->{template}->{$_[1]}) {
      carp "The key '$_[1]' doesn't exist in the hash.\n";
    }
    return $_[0][0]{$_[1]};
  }
}

1;
