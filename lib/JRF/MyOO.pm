#!/usr/bin/perl
#require 5.008;
{ package JRF::MyOO;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:16:38Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package main;
  our $DEBUG;
  $DEBUG = 1 if ! defined $DEBUG;
}

{
  package JRF::MyOO;
  ## 「俺様」流オブジェクト指向 (^^;のベースオブジェクト。
  ## The base object of the unbelievably profound
  ## Object-Oriented Programming way of mine. ;-)

  use Storable qw(dclone);
  use Carp;
  use JRF::Utils::HashFreezer;
  use JRF::Utils::Hooker;

  my %template = ("JRF::MyOO" => {cvar => {}});
  my %cvar = ("JRF::MyOO" => {});

  our $CVAR_DEBUG;

  sub extend_template {
    my $class = shift;
    my @hash = @_;
    if (exists $template{$class}) {
      $template{$class} = {%{$template{$class}}, @hash} if @hash;
    } else {
      $template{$class} =
        {(map {
                $_->extend_template() if ! exists $template{$_};
                %{$template{$_}};
              } (eval '@{' . $class . '::ISA}')),
         @hash
        };
    }
    return $template{$class};
  }

  sub extend_cvar {
    my $class = shift;
    my @hash = @_;
    if (exists $cvar{$class}) {
      $cvar{$class} = {%{$cvar{$class}}, @hash} if @hash;
    } else {
      $cvar{$class} =
        {(map {
                $_->extend_cvar() if ! exists $cvar{$_};
                %{$cvar{$_}};
              } (eval '@{' . $class . '::ISA}')),
         @hash
        };
    }
    return $cvar{$class};
  }

  sub get_template {
    my $class = shift;
    croak((ref $class) . "::get_template : requires class name not object.")
      if ref $class;
    return $class->extend_template();
  }

  sub get_cvar {
    my $class = shift;
    croak((ref $class) . "::get_cvar : requires class name not object.")
      if ref $class;
    return $class->extend_cvar();
  }

  sub clone {
    croak((ref $_[0]) . "::clone : forbidden.");
  }

  sub add_cvar_hook {
    my $self = shift;
    my ($name, $data) = @_;
    my $hooker = (tied %{$self->{cvar}})->[1];
    $hooker->{store_hook}->{$name} = []
      if ! exists $hooker->{store_hook}->{$name};
    push(@{$hooker->{store_hook}->{$name}}, $data);
  }

  sub remove_cvar_hook {
    my $self = shift;
    my ($name, $data) = @_;
    my $hooker = (tied %{$self->{cvar}})->[1];
    return undef if ! exists $hooker->{store_hook}->{$name};
    my $l = $hooker->{store_hook}->{$name};
    for (my $i = 0; $i < @$l; $i++) {
      if ($l->[$i] eq $data) {
	splice(@$l, $i, 1);
	return $data;
      }
    }
    return undef;
  }

  sub new {
    my $class = shift;
    my $obj;
    my $template = $class->get_template();
    my $cvar = $class->get_cvar();
    my $cdb = (defined $CVAR_DEBUG)? $CVAR_DEBUG : $main::DEBUG;
    if ($main::DEBUG) {
      $obj = {};
      tie %$obj, 'JRF::Utils::HashFreezer', (template => $template);
      %{$obj} = %{dclone($template)};
    } else {
      $obj = dclone($template);
    }
    if ($cdb) {
      my $cv = {};
      tie %$cv, 'JRF::Utils::Hooker', (template => $cvar,
				       store_hook => {}, fetch_hook => {});
      %{$cv} = %{$cvar};
      $obj->{cvar} = $cv;
    } else {
      %{$obj->{cvar}} = %{$cvar};
    }
    bless $obj, $class;
    return $obj;
  }

  my $_scalar_base;
  sub new_scalar {
    my ($self) = (!(ref $_[0]) || (ref $_[0])->isa(__PACKAGE__))?
      shift : undef;
    return dclone(\$_scalar_base);
  }
}

1;
