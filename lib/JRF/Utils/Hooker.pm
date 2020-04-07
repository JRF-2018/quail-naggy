#!/usr/bin/perl
#require 5.008;
{ package JRF::Utils::Hooker;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:16:17Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package JRF::Utils::Hooker;
  use Carp;
  use base qw(JRF::Utils::HashFreezer);

  sub STORE {
    my $self = shift;
    $self->SUPER::STORE(@_);
    unshift(@_, $self);
    if (exists $_[0][1]->{store_hook}->{$_[1]}) {
      my @hooks = @{$_[0][1]->{store_hook}->{$_[1]}};
      foreach my $h (@hooks) {
	next if ! ref $h;
	if ((ref $h) eq 'CODE') {
	  &{$h}($_[1], $_[2]);
	} elsif ((ref $h) eq 'ARRAY') {
	  my ($f, @opt) = @$h;
	  &{$f}(@opt, $_[1], $_[2]);
	} elsif (defined &{(ref $h) . "::process_command"}) {
	  $h->process_command($_[1], $_[2]);
	} else {
	  $h->{$_[1]} = $_[2];
	}
      }
    }
  }

  sub FETCH {
    if (exists $_[0][1]->{fetch_hook}->{$_[1]}) {
      my @hooks = @{$_[0][1]->{fetch_hook}->{$_[1]}};
      foreach my $h (@hooks) {
	next if ! ref $h;
	if ((ref $h) eq 'CODE') {
	  &{$h}($_[1]);
	} elsif ((ref $h) eq 'ARRAY') {
	  my ($f, @opt) = @$h;
	  &{$f}(@opt, $_[1]);
	} elsif (defined &{(ref $h) . "::process_command"}) {
	  $h->process_command($_[1]);
	}
      }
    }
    my $self = shift;
    $self->SUPER::FETCH(@_);
  }
}

1;
