#!/usr/bin/perl
#require 5.008;
{ package Naggy::Backend::CommandInterface;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:15:34Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy::Backend::CommandInterface;
  use base qw(JRF::MyOO);

  __PACKAGE__->extend_template
    (
     ngb => undef,
    );

#  __PACKAGE__->extend_cvar
#    (
#     ABBREV_echo => "echo",
#    );

#  sub echo {
#    my $self = shift;
#    $self->{ngb}->rprint(join(" ", @_));
#  }

  sub process_command {
    my $self = shift;
    my ($cmd, @args) = @_;
    $cmd =~ s/\-/_/g;
    $cmd = $self->{cvar}->{"ABBREV_" . $cmd}
      if exists $self->{cvar}->{"ABBREV_" . $cmd};

    if (defined $cmd && (ref $cmd) eq 'CODE') {
      &{$cmd}($self, @args);
      return;
    } elsif (defined $cmd && defined &{(ref $self) . "::" . $cmd}) {
      no strict;
      &{(ref $self) . "::" . $cmd}($self, @args);
      return;
    }

    $self->{ngb}->rerror("unknown command: $cmd.");
  }

  sub new {
    my $class = shift;
    my ($ngb, @rest) = @_;
    my $obj =  $class->SUPER::new(@rest);
    $obj->{ngb} = $ngb;
    return $obj;
  }
}

1;
