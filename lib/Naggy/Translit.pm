#!/usr/bin/perl
#require 5.008;
{ package Naggy::Translit;
  our $VERSION = "0.07"; # Time-stamp: <2017-04-28T07:14:57Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy::Translit;
  use base qw(JRF::MyOO);

  use Encode qw();
  use Naggy;
  use JRF::Utils qw(:all);

  __PACKAGE__->extend_template
    (
     type => "translit",
     case_sensitive => 1,
     max_length_table => {},
     table => {},
     ideo => {},
     completion_beginning => undef,
     auto_insert_first => undef,
     auto_insert_last => undef,
     recursive => 0,
     is_loaded => 1,
    );

  sub load_from_string {
    my $self = (ref $_[0])? shift : __PACKAGE__->new();
    my ($src, %opt) = @_;
    $self->{case_sensitive} = $opt{case_sensitive}
      if exists $opt{case_sensitive};
    my $inversely = exists $opt{inversely} && $opt{inversely};

    my $intable = 0;
    my @line = split(/\n/, $src);
    while (@line) {
      my $s = Naggy::next_line(\@line);
      $s =~ s/^\s+//;
      $s =~ s/\s+$//;

      if (! $intable && $s =~ /^\.\S/) {
	$s =~ s/^\.//;
	if ($s =~ /^case[- ]sensitive$/i 
	    || ($s =~ /^case[- ]sensitive\s+(\S.*)$/i
		&& Naggy::is_true($1))) {
	  $self->{case_sensitive} = 1;
	} elsif ($s =~ /^case[- ]insensitive$/i 
		 || ($s =~ /^case[- ]sensitive\s+(\S.*)$/i
		     && ! Naggy::is_true($1))) {
	  $self->{case_sensitive} = 0;
	} elsif ($s =~ /^completion[- ]beginning\s+/i) {
	  my @l = map {Naggy::unescape_string($_)} split(/\s+/, $');
	  my $tmp = $self->{completion_beginning};
	  foreach my $w (@l) {
	    if ($self->{case_sensitive}) {
	      if (defined $tmp) {
		$tmp = qr/$tmp|\Q$w\E/;
	      } else {
		$tmp = qr/\Q$w\E/;
	      }
	    } else {
	      if (defined $tmp) {
		$tmp = qr/$tmp|\Q$w\E/i;
	      } else {
		$tmp = qr/\Q$w\E/i;
	      }
	    }
	  }
	  $self->{completion_beginning} = $tmp;
	} elsif ($s =~ /^auto[- ]insert[- ]first\s+(\S+)$/i) {
	  $self->{auto_insert_first} = Naggy::unescape_string($1);
	} elsif ($s =~ /^auto[- ]insert[- ]last\s+(\S+)$/i) {
	  $self->{auto_insert_last} = Naggy::unescape_string($1);
	} elsif ($s =~ /^recursive(?:\s+(?:true|1))?$/i) {
	  $self->{recursive} = 1;
	}
	$s = "";
      }

      next if $s eq "";

      if (! $intable && $inversely) {
	$self->{completion_beginning} = undef;
	$self->{auto_insert_first} = undef;
	$self->{auto_insert_last} = undef;
	$self->{recursive} = 0;
	$self->{case_sensitive} = 1;
      }

      $intable = 1;

      my ($from, $to, $ideo) = split(/\s+/, $s);
      if ($inversely) {
	my $tmp = $from;
	$from = $to;
	$to = $tmp;
	$ideo = undef;
      }

      $from = Naggy::unescape_string($from);
      next if $from eq "";
      $to = Naggy::unescape_string($to) if defined $to;
      $to = $from if ! defined $to;
      $ideo = Naggy::unescape_string($ideo) if defined $ideo;
      $from = uc($from) if ! $self->{case_sensitive};
      my $c = substr($from, 0, 1);
      if (! exists $self->{table}->{$from}) {
	if (! exists $self->{max_length_table}->{$c}
	    || length($from) > $self->{max_length_table}->{$c}) {
	  $self->{max_length_table}->{$c} = length($from);
	}
	$self->{table}->{$from} = $to;
      }
      $self->{ideo}->{$from} = $ideo
	if defined $ideo && ! exists $self->{ideo}->{$from};
    }

    return $self;
  }

  sub put {
    my $self = shift;
    my ($from, $to) = @_;
    $from = uc($from) if $self->{case_sensitive};
    if (! exists $self->{table}->{$from}) {
      my $c = substr($from, 0, 1);
      if (! exists $self->{max_length_table}->{$c}
	  || length($from) > $self->{max_length_table}->{$c}) {
	$self->{max_length_table}->{$c} = length($from);
      }
    }
    $self->{table}->{$from} = $to;
  }

  sub remove {
    my $self = shift;
    my ($key) = @_;
    $key = uc($key) if $self->{case_sensitive};
    return undef if ! exists $self->{table}->{$key};
    my $r = delete $self->{table}->{$key};
    my $c = substr($key, 0, 1);
    return $r if length($key) < $self->{max_length_table}->{$c};
    my @l = grep {substr($_, 0, 1) eq $c} (keys %{$self->{table}});
    if (! @l) {
      delete $self->{max_length_table}->{$c};
    } else {
      my $max = 0;
      foreach my $k (@l) {
	$max = length($k) if $max < length($k);
      }
      $self->{max_length_table}->{$c} = $max;
    }
    return $r;
  }

  sub load_trl {
    my $self = (ref $_[0])? shift : undef;
    my ($f, %opt) = @_;
    my $enc = Encode::find_encoding('utf8');
    open(my $fh,  "<", encode_fn($f)) or return undef;
    binmode($fh, ":raw");
    my $src = join("", <$fh>);
    my @line = split(/\n/, $src);
    close($fh);
    while (@line) {
      my $s = shift(@line);
      last if $s =~ /^\s*$/;
      $s =~ s/\#.*//s;
      next if $s =~ /^\s*$/;
      last if $s !~ /^\s*\./;
      if ($s =~ /^\s*\.\s*encoding\s+(\S+)\s*$/i) {
	$enc = Encode::find_encoding($1);
	last;
      }
    }
    $src = $enc->decode($src);
    if (defined $self) {
      return $self->load_from_string($src, %opt);
    } else {
      return load_from_string($src, %opt);
    }
  }

  sub load_wnd {
    my $self = (ref $_[0])? shift : undef;
    my ($f) = @_;
    my $src = "";
    open(my $fh, "<", encode_fn($f)) or return undef;
    binmode($fh, ":encoding(cp932):crlf");
    while (<$fh>) {
      chomp;
      if (/\t/) {
	my ($from, $to) = split(/\t/, $_);
	$src .= Naggy::escape_string($from) . "\t"
	  . Naggy::escape_string($to) . "\n";
      }
    }
    close($fh);
    if (defined $self) {
      return $self->load_from_string($src, case_sensitive => 0);
    } else {
      return load_from_string($src, case_sensitive => 0);
    }
  }

  sub load_file {
    my $f = (ref $_[0])? $_[1] : $_[0];

    if ($f =~ /\.wnd$/i) {
      return load_wnd(@_);
    } else {
      return load_trl(@_);
    }
  }

  sub translit {
    my $self = shift;
    my ($src) = @_;
    my $dest = "";
    if (defined $self->{auto_insert_first}) {
      $src = $self->{auto_insert_first} . $src;
    }
    if (defined $self->{auto_insert_last}) {
      $src .= $self->{auto_insert_last};
    }

    while (1) {
      my $prev = $src;
      $dest = "";

      while (length($src) > 0) {
	my $c = substr($src, 0, 1);
	$c = uc($c) if ! $self->{case_sensitive};
	if (! exists $self->{max_length_table}->{$c}) {
	  $dest = $dest . $c;
	  $src = substr($src, 1);
	} else {
	  my $done = 0;
	  for (my $len = $self->{max_length_table}->{$c}; $len > 0; $len--) {
	    next if length($src) < $len;
	    my $from = substr($src, 0, $len);
	    $from = uc($from) if ! $self->{case_sensitive};
	    if (exists $self->{table}->{$from}) {
	      $dest = $dest . $self->{table}->{$from};
	      $src = substr($src, $len);
	      $done = 1;
	      last;
	    }
	  }
	  if (! $done) {
	    $dest = $dest . $c;
	    $src = substr($src, 1);
	  }
	}
      }

      last if ! $self->{recursive} || $dest eq $prev;
      $src = $dest;
    }

    return $dest;
  }
}

{
  package Naggy::Translit::Function;
  use base qw(Naggy::Translit);

  use Carp;

  __PACKAGE__->extend_template
    (
     function => undef,
    );

  sub new {
    my $class = shift;
    my $obj =  $class->SUPER::new(@_);
    my ($f) = @_;
    $obj->{function} = $f;
    return $obj;
  }

  sub translit {
    my $self = shift;
    return &{$self->{function}}(@_);
  }
}

{
  package Naggy::Translit::AutoLoader;
  use base qw(Naggy::Translit);

  __PACKAGE__->extend_template
    (
     auto_load => undef,
    );

  sub new {
    my $class = shift;
    my $obj =  $class->SUPER::new();
    my ($f, @opt) = @_;
    $obj->{auto_load} = [$f, @opt];
    $obj->{is_loaded} = 0;
    return $obj;
  }

  sub load_now {
    my $self = shift;
    my $f = $self->{auto_load}->[0];
    die "$f: $!" if ! defined  $self->load_file(@{$self->{auto_load}});

    $self->{is_loaded} = 1;
  }

  sub put {
    my $self = shift;
    $self->load_now() if ! $self->{is_loaded};

    return $self->SUPER::put(@_);
  }

  sub remove {
    my $self = shift;
    $self->load_now() if ! $self->{is_loaded};

    return $self->SUPER::remove(@_);
  }

  sub translit {
    my $self = shift;
    $self->load_now() if ! $self->{is_loaded};

    return $self->SUPER::translit(@_);
  }
}

1;
