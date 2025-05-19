#!/usr/bin/perl
#require 5.008;
{ package Naggy::Backend;
  our $VERSION = "0.18"; # Time-stamp: <2021-12-24T07:21:35Z>
}

use strict;
use warnings;
#no autovivification qw(strict warn fetch exists delete store);
use utf8; # Japanese English

{
  package Naggy::Backend;
  use base qw(JRF::MyOO);
  use JRF::Resource qw(locate_file_resource);

  our $VERSION = $Naggy::Backend::VERSION;

  use Encode qw();
  use File::Spec;
  use JRF::Utils qw(:all);
  use Naggy;
  use Naggy::Backend::Translit;
  use Naggy::SKKDic;
  use Naggy::TankanjiDic;
  use Naggy::Backend::Convert;

  __PACKAGE__->extend_template
    (
     INIT_FILE => undef,
     BATCH_MODE => undef,
     UNSAFE => 0,
     IN_INIT_FILE => 0,
     INIT_LOG => "",
     INIT_TAIL => "",
     INIT_VAR => {%ENV, "\$" => "\$"},
     INIT_VAR_STACK => {},
     translit => undef,
     convert => undef,
     convert_translit => "alpha-hira",
     command => {},
    );

  __PACKAGE__->extend_cvar
    (
     current => [],
    );

  our %COMMAND;
  our %MINILISP_COMMAND;
  our %UNSAFE_COMMAND;
  our %TEST_COMMAND;

  sub new {
    my $class = shift;
    my $obj =  $class->SUPER::new(@_);
    my %opt = @_;
    my %cmd = %COMMAND;
    if (! exists $opt{MINILISP} || $opt{MINILISP}) {
      %cmd = (%cmd, %MINILISP_COMMAND);
    }
    if (exists $opt{UNSAFE} && $opt{UNSAFE}) {
      $obj->{UNSAFE} = $opt{UNSAFE};
      %cmd = (%cmd, %UNSAFE_COMMAND);
    }
    if (defined $main::DEBUG && $main::DEBUG) {
      %cmd = (%cmd, %TEST_COMMAND);
    }
    %{$obj->{command}} = %cmd;

    if (exists $opt{PUNCTUATION_FULLWIDTH_PERIOD}) {
      $obj->{INIT_VAR}->{JAPANESE_PUNCT_PERIOD}
    	= $opt{PUNCTUATION_FULLWIDTH_PERIOD};
    } else {
      $obj->{INIT_VAR}->{JAPANESE_PUNCT_PERIOD} = 0;
    }
    if (exists $opt{KBKANA}) {
      $obj->{INIT_VAR}->{JAPANESE_KBKANA} = $opt{KBKANA};
    } else {
      $obj->{INIT_VAR}->{JAPANESE_KBKANA} = 0;
    }

    if (exists $opt{translit}) {
      $obj->{translit} = $opt{translit};
    } else {
      $obj->{translit} = Naggy::Backend::Translit->new(%opt);
    }
    $obj->{convert} = Naggy::Backend::Convert->new($obj, %opt);

    return $obj;
  }

  sub push_current {
    my $self = shift;
    push(@{$self->{cvar}->{current}}, $self);
  }
  sub pop_current {
    my $self = shift;
    pop(@{$self->{cvar}->{current}});
  }

  sub rprint {
    my $self = (ref $_[0])? shift : undef;
    my ($s) = @_;
    if (! defined $self) {
      my $l = __PACKAGE__->get_cvar()->{current};
      if (@$l > 0) {
	$self = $l->[$#$l];
      }
    }

    # print in local setting.
    if (defined $self && $self->{IN_INIT_FILE}) {
      $self->{INIT_TAIL} = $s;
      $self->{INIT_LOG} .= $self->{INIT_TAIL};
    } elsif (defined $self && defined $self->{BATCH_MODE}) {
      print STDERR $s;
    } else {
      print $s;
    }
  }

  sub rerror {
    my $self = (ref $_[0])? shift : undef;
    my ($s) = @_;
    $s = "# error " . Naggy::escape_string($s) . "\n";
    if (defined $self) {
      $self->rprint($s);
    } else {
      rprint $s;
    }
  }

  sub rinfo {
    my $self = (ref $_[0])? shift : undef;
    my ($s) = @_;

    $s = "# info " . Naggy::escape_string($s) . "\n";
    if (defined $self) {
      $self->rprint($s);
    } else {
      rprint $s;
    }
  }

  sub rwarn {
    my $self = (ref $_[0])? shift : undef;
    my ($s) = @_;

    $s = "# warn " . Naggy::escape_string($s) . "\n";
    if (defined $self) {
      $self->rprint($s);
    } else {
      rprint $s;
    }
  }

  sub load_init_file {
    my $self = shift;
    my $f = shift;
    my %opt = @_;

    my $r = open(my $fh, "<", encode_fn($f));
    if (! $r) {
      rerror "load_init_file: $f: $!";
      return 0;
    }
    binmode($fh, ":utf8");
    my $s = join("", <$fh>);
    close($fh);

    return $self->load_init_file_from_string($s, filename => $f, %opt);
  }

  sub load_init_file_from_string {
    my $self = shift;
    my $content = shift;
    my %opt = (filename => "STRING", @_);
    my $f = $opt{filename};

    my @line = split(/\n/, $content);

    $self->push_current();

    my @if;
    my $if_state = 1;
    ## $if_state: 0: may else. 1: may if. 2: in if in if false.
    ##    3: in else(do). 4: in else(don't)
    my $prev = $self->{IN_INIT_FILE};
    $self->{IN_INIT_FILE} = 1;

    while (@line) {
      $_ = Naggy::next_line(\@line);
      s/^\s+//;
      s/\s+$//;

      s(\$\{([^\}]+)\}){
	my $name = $1;
	if (length($name) > 3 && substr($name, -2) eq ':e') {
	  $name = substr($name, 0, -2);
	  if (exists $self->{INIT_VAR}->{$name}) {
	    my $s = Naggy::escape_string($self->{INIT_VAR}->{$name});
	    $s =~ s/\|/\\u\{7C\}/g;
	    $s;
	  } else {
	    "\\0";
	  }
	} elsif (exists $self->{INIT_VAR}->{$1}) {
	  $self->{INIT_VAR}->{$1};
	} else {
	  ""
	}
      }gsex;

      if (s/^\.\s*//) {
	if ($if_state == 0 || $if_state == 2 || $if_state == 4) {
	  if (/^endif$/i) {
	    if (@if) {
	      $if_state = pop(@if);
	    } else {
	      rerror "$f: Endif without if.";
	      $self->{IN_INIT_FILE} = $prev;
	      $self->pop_current();
	      return 0;
	    }
	  } elsif (/^if(?:\s|$)/i) {
	    push(@if, $if_state);
	    $if_state = 2;
	  } elsif (/^else$/i) {
	    if ($if_state == 0) {
	      $if_state = 3;
	    } elsif ($if_state == 4) {
	      rerror "$f: Double else.";
	      $self->{IN_INIT_FILE} = $prev;
	      $self->pop_current();
	      return 0;
	    } else {
	      $if_state = 2;
	    }
	  }
	  next;
	} else {
	  if (/^set\s+(\S+)\s+(\S.*)$/i) {
	    $self->{INIT_VAR}->{$1} = $2;
	  } elsif (/^set\s+(\S+)$/i) {
	    $self->{INIT_VAR}->{$1} = "";
	  } elsif (/^unset\s+(\S+)$/i) {
	    delete $self->{INIT_VAR}->{$1}
	      if exists $self->{INIT_VAR}->{$1};
	  } elsif (/^set-u\s+(\S+)\s+(\S.*)$/i) {
	    $self->{INIT_VAR}->{$1} = Naggy::unescape_string($2);
	  } elsif (/^set-u\s+(\S+)$/i) {
	    $self->{INIT_VAR}->{$1} = "";
	  } elsif ($self->{UNSAFE} && /^push\s+(\S+)\s*$/i) {
	    my $n = $1;
	    my $s = $';
	    $s =~ s/^\s+//;
	    $s =~ s/\s+$//;
	    $self->{INIT_VAR_STACK}->{$n} = [] if ! exists $self->{INIT_VAR_STACK}->{$n};
	    if (exists $self->{INIT_VAR}->{$n}) {
	      push(@{$self->{INIT_VAR_STACK}->{$n}}, $self->{INIT_VAR}->{$n});
	    } else {
	      push(@{$self->{INIT_VAR_STACK}->{$n}}, undef);
	    }
	    if ($s ne "") {
	      $self->{INIT_VAR}->{$n} = $s;
	    }
	  } elsif ($self->{UNSAFE} && /^pop\s+(\S+)$/i) {
	    my $n = $1;
	    if (exists $self->{INIT_VAR_STACK}->{$n}) {
	      my $v = pop(@{$self->{INIT_VAR_STACK}->{$n}});
	      if (defined $v) {
		$self->{INIT_VAR}->{$n} = $v;
	      } else {
		delete $self->{INIT_VAR}->{$n};
	      }
	      delete $self->{INIT_VAR_STACK}->{$n} if @{$self->{INIT_VAR_STACK}->{$n}} == 0;
	    }
	  } elsif (/^if\s+/i) {
	    my $r = 0;
	    push(@if, $if_state);

	    foreach my $expr (split(/\s+\|\|\s+/, $')) {
	      $expr =~ s/^\s+//;
	      $expr =~ s/\s+$//;

	      if ($expr =~ /^is-true\s*/i) {
		my $s = $';
		$s =~ s/^\s+//;
		$s =~ s/\s+$//;
		$r = Naggy::is_true($s);
	      } elsif ($expr =~ /^!\s*is-true\s*/i) {
		my $s = $';
		$s =~ s/^\s+//;
		$s =~ s/\s+$//;
		$r = ! Naggy::is_true($s);
	      } elsif ($expr =~ /^defined\s+(\S+)$/i) {
		$r = exists $self->{INIT_VAR}->{$1};
	      } elsif ($expr =~ /^!\s*defined\s+(\S+)$/i) {
		$r = ! exists $self->{INIT_VAR}->{$1};
	      } elsif ($expr =~ /^empty$/i) {
		$r = 1;
	      } elsif ($expr =~ /^!\s*empty\s+\S/i) {
		$r = 1;
	      } elsif ($expr =~ /^number\s+[01-9]+(?:\.[01-9]+)?$/i) {
		$r = 1;
	      } elsif ($expr =~ /^!\s*number\s*$/i) {
		my $s = $';
		$r = ($s !~ /^[01-9]+(?:\.[01-9]+)$/);
	      } elsif ($expr =~ /^strinstr\s+(\S+)\s*/i) {
		my $m = $1;
		my $s = $';
		$r = ($s =~ /\Q$m\E/s);
	      } elsif ($expr =~ /^!\s*strinstr\s+(\S+)\s*/i) {
		my $m = $1;
		my $s = $';
		$r = ($s !~ /\Q$m\E/s);
	      } elsif ($expr =~ /^(.*)\s+==\s+(.*)$/) {
		my $a = $1;
		my $b = $2;
		$a =~ s/^\s+//;
		$a =~ s/\s+$//;
		$b =~ s/^\s+//;
		$b =~ s/\s+$//;
		if ($a =~ /^[01-9\.]+$/ && $b =~ /^[01-9\.]+$/) {
		  $r = ($a == $b);
		} else {
		  $r = ($a eq $b);
		}
	      } elsif ($expr =~ /^(.*)\s+!=\s+(.*)$/) {
		my $a = $1;
		my $b = $2;
		$a =~ s/^\s+//;
		$a =~ s/\s+$//;
		$b =~ s/^\s+//;
		$b =~ s/\s+$//;
		if ($a =~ /^[01-9\.]+$/ && $b =~ /^[01-9\.]+$/) {
		  $r = ($a != $b);
		} else {
		  $r = ($a ne $b);
		}
	      } elsif ($expr =~ /^(.*)\s+>=\s+(.*)$/) {
		my $a = $1;
		my $b = $2;
		$a =~ s/^\s+//;
		$a =~ s/\s+$//;
		$b =~ s/^\s+//;
		$b =~ s/\s+$//;
		$r = ($a >= $b);
	      } elsif ($expr =~ /^(.*)\s+<=\s+(.*)$/) {
		my $a = $1;
		my $b = $2;
		$a =~ s/^\s+//;
		$a =~ s/\s+$//;
		$b =~ s/^\s+//;
		$b =~ s/\s+$//;
		$r = ($a <= $b);
	      } elsif ($expr =~ /^(.*)\s+>\s+(.*)$/) {
		my $a = $1;
		my $b = $2;
		$a =~ s/^\s+//;
		$a =~ s/\s+$//;
		$b =~ s/^\s+//;
		$b =~ s/\s+$//;
		$r = ($a > $b);
	      } elsif ($expr =~ /^(.*)\s+<\s+(.*)$/) {
		my $a = $1;
		my $b = $2;
		$a =~ s/^\s+//;
		$a =~ s/\s+$//;
		$b =~ s/^\s+//;
		$b =~ s/\s+$//;
		$r = ($a < $b);
#	      } elsif ($expr =~ /^!\s*$/i) {
#		my $s = $';
#		$s =~ s/^\s+//;
#		$s =~ s/\s+$//;
#		$r = ! Naggy::is_true($s);
#	      } else {
#		my $s = $expr;
#		$s =~ s/^\s+//;
#		$s =~ s/\s+$//;
#		$r = Naggy::is_true($s);
	      } else {
		rerror "$f: Illegal if-expression.";
		$self->{IN_INIT_FILE} = $prev;
		$self->pop_current();
		return 0;
	      }
	      last if $r;
	    }
	    $if_state = !! $r;
	  } elsif (/^else$/i) {
	    if ($if_state == 1) {
	      if (@if) {
		$if_state = 4;
	      } else {
		rerror "$f: Else without if.";
		$self->{IN_INIT_FILE} = $prev;
		$self->pop_current();
		return 0;
	      }
	    } else {
	      rerror "$f: Double else.";
	      $self->{IN_INIT_FILE} = $prev;
	      $self->pop_current();
	      return 0;
	    }
	  } elsif (/^endif$/i) {
	    if (@if) {
	      $if_state = pop(@if);
	    } else {
	      rerror "$f: Endif without if.";
	      $self->{IN_INIT_FILE} = $prev;
	      $self->pop_current();
	      return 0;
	    }
	  } else {
	    rerror "cannot interpret # $_";
	    $self->{IN_INIT_FILE} = $prev;
	    $self->pop_current();
	    return 0;
	  }
	  next;
	}
      }

      next if ! ($if_state & 1);

      s/^\s+//;
      s/\s+$//;

      next if $_ eq "";

      $self->{INIT_LOG} .= $_ . "\n";

      my $prev_log_len = length($self->{INIT_LOG});

      my ($cmd, @args) = map {Naggy::unescape_string($_)} split(/\s+/, $_);
      if ($cmd eq "return") {
	if (@args) {
	  $self->{INIT_VAR}->{"RESULT"} = join(" ", @args);
	} else {
	  delete $self->{INIT_VAR}->{"RESULT"};
	}
	rinfo "return from $f.";
	last;
      } elsif ($cmd eq "return-e") {
	$self->{INIT_VAR}->{"RESULT"} = join(" ", map {Naggy::escape_string($_)} @args);
	rinfo "return from $f.";
	last;
      } else {
	$self->process_command($cmd, @args);
      }

      my $output = substr($self->{INIT_LOG}, $prev_log_len);
      if ($output =~ /\# begin\s+\S+\n(.*)\n\# end/is) {
	$self->{INIT_VAR}->{"RESULT"} = Naggy::unescape_string($1);
      } elsif ($self->{INIT_TAIL} =~ /^# error/) {
	$self->{IN_INIT_FILE} = $prev;
	$self->pop_current();
	return 0;
      } else {
	delete $self->{INIT_VAR}->{"RESULT"};
      }
    }

    $self->{IN_INIT_FILE} = $prev;

    $self->pop_current();

    return 1;
  }

  sub process_command {
    my $self = shift;
    my ($cmd, @args) = @_;
#    print "do $cmd " . join(" ", @args) . "\n";
    if (! exists $self->{command}->{$cmd}) {
      $self->rerror("unknown command: $cmd.");
    } else {
      eval {
	my $c = $self->{command}->{$cmd};
	if (! (ref $c) || 'CODE' eq (ref $c)) {
	  &{$c}($self, @args);
	} elsif ((ref $c) eq 'ARRAY') {
	  my ($f, @rest) = @$c;
	  &{$f}($self, @rest, @args);
	} else {
	  $c->process_command($cmd, @args);
	}
      };
      if ($@) {
	$self->rerror("$cmd: $@");
      }
    }
  }

 ClassInit:
  {
    $COMMAND{"nop"} = sub {
      rprint "# begin unit\ntrue\n# end\n";
    };
    $COMMAND{"exit"} = sub {
      rprint "# begin unit\nbye\n# end\n";
      exit(0);
    };
    $COMMAND{"bye"} = $COMMAND{exit};

    $COMMAND{"version"} = sub {
      rprint "# begin string\n";
      rprint Naggy::escape_string($VERSION) . "\n";
      rprint "# end\n";
    };

    $COMMAND{"set"} =sub {
      my $self = shift;
      my ($n, $v) = @_;
      if (@_ != 1 && @_ != 2) {
	rerror "set: illegal arguments.";
	return;
      }
      if (@_ == 1) {
	$self->{INIT_VAR}->{$n} = "";
      } else {
	$self->{INIT_VAR}->{$n} = $v;
      }
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"unset"} =sub {
      my $self = shift;
      my ($n, $v) = @_;
      if (@_ != 1) {
	rerror "unset: illegal arguments.";
	return;
      }
      delete $self->{INIT_VAR}->{$n} if exists $self->{INIT_VAR}->{$n};
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"get"} =sub {
      my $self = shift;
      if (@_ != 1) {
	rerror "get: illegal arguments.";
	return;
      }
      my ($v) = @_;
      if (! exists $self->{INIT_VAR}->{$v}) {
	rerror "get: The variable doesn't exist.";
	return;
      } else {
	rprint "# begin string\n";
	rprint Naggy::escape_string($self->{INIT_VAR}->{$v}) . "\n";
	rprint "# end\n";
      }
    };

    $TEST_COMMAND{"base64test"} = sub {
      use MIME::Base64;

      rprint "# begin base64\n" . encode_base64("OK base64") . "\n" . "# end\n";
    };

    $TEST_COMMAND{"listtest"} = sub {
      rprint "# begin list\na b c\nc d \\0 e ニホンゴ\n# end\n";
    };

    $TEST_COMMAND{"warntest"} = sub {
      rprint "# warn test warn.\n";
      rprint "# begin list\nOK\n";
      rprint "# info test info.\n";
      rprint "# end\n";
    };

    $COMMAND{"translit"} = sub {
      my $self = shift;
      my ($spec, $s) = @_;
      if (@_ != 2) {
	rerror "translit: illegal arguments.";
	return;
      }
      my $r = $self->{translit}->translit($spec, $s);
      if (defined $r) {
	rprint "# begin string\n";
	rprint Naggy::escape_string($r) . "\n";
	rprint "# end\n";
      } else {
	rerror "translit: failed.";
      }
    };

    $COMMAND{"translit-with-space"} = sub {
      my $self = shift;
      my ($spec, $s) = @_;
      if (@_ != 2) {
	rerror "translit-with-space: illegal arguments.";
	return;
      }
      my $r = $s;
      $r =~ s(\S+){
	$self->{translit}->translit($spec, $&);
      }gsex;

      if (defined $r) {
	rprint "# begin string\n";
	rprint Naggy::escape_string($r) . "\n";
	rprint "# end\n";
      } else {
	rerror "translit-with-space: failed.";
      }
    };

    $COMMAND{"load-translit"} = sub {
      my $self = shift;
      my ($spec, $fn) = @_;
      if (@_ != 2) {
	rerror "load-translit: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "load-translit: illegal name which contains a space.";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "load-translit: $fn: not found or unavailable.";
	return;
      }
      my $r = Naggy::Translit::load_file($file);
      if (! defined $r) {
	rerror "load-translit: $file: $!";
	return;
      }
      $self->{translit}->{table}->{$spec} = $r;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"load-translit-inversely"} = sub {
      my $self = shift;
      my ($spec, $fn) = @_;
      if (@_ != 2) {
	rerror "load-translit-inversely: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "load-translit-inversely: illegal name which contains a space.";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "load-translit-inversely: $fn: not found or unavailable.";
	return;
      }
      my $r = Naggy::Translit::load_file($file, inversely => 1);
      if (! defined $r) {
	rerror "load-translit-inversely: $file: $!";
	return;
      }
      $self->{translit}->{table}->{$spec} = $r;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"load-translit-from-string"} = sub {
      my $self = shift;
      my ($spec, @src) = @_;
      if (@_ < 2) {
	rerror "load-translit-from-string: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "load-translit-from-string: illegal name which contains a space.";
	return;
      }
      my $r = Naggy::Translit::load_from_string(join("\n", @src));
      if (! defined $r) {
	rerror "load-translit-from-string: cannot make translit table.";
	return;
      }
      $self->{translit}->{table}->{$spec} = $r;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"auto-load-translit"} = sub {
      my $self = shift;
      my ($spec, $fn) = @_;
      if (@_ != 2) {
	rerror "auto-load-translit: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "auto-load-translit: illegal name which contains a space.";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "auto-load-translit: $fn: not found or unavailable.";
	return;
      }
      my $r = Naggy::Translit::AutoLoader->new($file);
      $self->{translit}->{table}->{$spec} = $r;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"auto-load-translit-inversely"} = sub {
      my $self = shift;
      my ($spec, $fn) = @_;
      if (@_ != 2) {
	rerror "auto-load-translit-inversely: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "auto-load-translit-inversely: illegal name which contains a space.";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "auto-load-translit-inversely: $fn: not found or unavailable.";
	return;
      }
      my $r = Naggy::Translit::AutoLoader->new($file, inversely => 1);
      $self->{translit}->{table}->{$spec} = $r;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"abbrev-translit"} = sub {
      my $self = shift;
      my ($spec, @specs) = @_;
      if ($spec =~ /\s+/) {
	rerror "abbrev-translit: illegal name which contains a space.";
	return;
      }
      if (@specs == 0) {
	delete $self->{translit}->{table}->{$spec};
      } elsif (@specs == 1) {
	$self->{translit}->{table}->{$spec} = $specs[0];
      } else {
	$self->{translit}->{table}->{$spec} = [@specs];
      }
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"rename-translit"} = sub {
      my $self = shift;
      my ($from, $to) = @_;
      if (@_ != 2) {
	rerror "rename-translit: illegal arguments.";
	return;
      }
      if ($from =~ /\s+/ || $to =~ /\s+/ || $from !~ /\S/ || $to !~ /\S/) {
	rerror "rename-translit: illegal name.";
	return;
      }
      $self->{translit}->rename($from, $to);
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"charmap-of-translit"} = sub {
      my $self = shift;
      my ($spec) = @_;
      if (@_ != 1) {
	rerror "charmap-of-translit: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "charmap-of-translit: illegal name which contains a space.";
	return;
      }
      my $charmap = $self->{translit}->alpha_charmap($spec);
      if (! defined $charmap) {
	rerror "charmap-of-translit: cannot make charmap.";
      } else {
	rprint "# begin list\n";
	rprint "data\n";
	foreach my $key (sort keys %{$charmap}) {
	  rprint Naggy::escape_string($key) . " "
	    . Naggy::escape_string($charmap->{$key}) . "\n";
	}
	rprint "# end\n";
      }
    };

    $COMMAND{"complete-by-translit"} = sub {
      my $self = shift;
      my ($spec, $s) = @_;
      if (@_ != 2) {
	rerror "complete-by-translit: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "complete-by-translit: illegal name which contains a space.";
	return;
      }
      my $r = $self->{translit}->complete($spec, $s);
      if (! defined $r) {
	rerror "complete-by-translit: failed.";
      } else {
	my $compl = $r->{completion};
	$compl = "" if ! defined $compl;
	rprint "# begin list\n";
	rprint "prefix " . Naggy::escape_string($r->{prefix}) . "\n";
	rprint "word " . Naggy::escape_string($r->{word}) . "\n";
	rprint "completion " . Naggy::escape_string($compl) . "\n";
	rprint "data\n";
	my @word;
	my @other;
	foreach my $k (keys %{$r->{map}}) {
	  if ($k =~ /^[A-Za-z]/) {
	    push(@word, $k);
	  } else {
	    push(@other, $k);
	  }
	}
	foreach my $k (sort(@word), sort(@other)) {
	  rprint Naggy::escape_string($k) . " "
	    . Naggy::escape_string($r->{map}->{$k}) . "\n";
	}
	rprint "# end\n";
      }
    };

    $COMMAND{"list-translit"} = sub {
      my $self = shift;
      if (@_ != 0) {
	rerror "list-translit: illegal arguments.";
	return;
      }
      rprint "# begin list\n";
      foreach my $k (sort keys %{$self->{translit}->{table}}) {
	my $spec = $self->{translit}->{table}->{$k};
	if (ref($spec) eq 'ARRAY') {
	  $spec = join(" ", @{$spec});
	}
	rprint Naggy::escape_string($k) . " "
	  . Naggy::escape_string($spec) . "\n";
      }
      rprint "# end\n";
    };

    $COMMAND{"add-convert-name-translit"} = sub {
      my $self = shift;
      my ($name, $spec) = @_;
      if (@_ != 2) {
	rerror "add-convert-name-translit: illegal arguments.";
	return;
      }
      if ($spec =~ /\s+/) {
	rerror "add-convert-name-translit: illegal translit name which contains a space.";
	return;
      }
      $self->{convert}->{table}->{$name} = ["translit", $spec];
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"add-convert-name-skk"} = sub {
      my $self = shift;
      my ($name) = @_;
      if (@_ != 1) {
	rerror "add-convert-name-skk: illegal arguments.";
	return;
      }
      $self->{convert}->{table}->{$name} = ["convert", "skk"];
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"add-convert-name-tankanji"} = sub {
      my $self = shift;
      my ($name) = @_;
      if (@_ != 1) {
	rerror "add-convert-name-tankanji: illegal arguments.";
	return;
      }
      $self->{convert}->{table}->{$name} = ["convert", "tankanji"];
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"add-convert-name-unicode"} = sub {
      my $self = shift;
      my ($name) = @_;
      if (@_ != 1) {
	rerror "add-convert-name-unicode: illegal arguments.";
	return;
      }
      $self->{convert}->{table}->{$name} = ["convert", "unicode"];
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"delete-convert-name"} = sub {
      my $self = shift;
      my ($name) = @_;
      if (@_ != 1) {
	rerror "delete-convert-name: illegal arguments.";
	return;
      }
      delete $self->{convert}->{table}->{$name}
	if exists $self->{convert}->{table}->{$name};
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"set-tankanji-dic"} = sub {
      my $self = shift;
      if (@_ != 1 && @_ != 2) {
	rerror "set-tankanji-dic: illegal arguments.";
	return;
      }
      my ($fn, $eflag) = @_;
      $eflag = "-u" if ! defined $eflag;
      my $e;
      if ($eflag eq "-e") {
	if ($Resource::USE_JISX0213) {
	  $e = "euc-jisx0213";
	} else {
	  $e = "euc-jp";
	}
      } elsif ($eflag eq "-s") {
	$e = "cp932";
      } elsif ($eflag eq "-u") {
	$e = "utf8";
      } else {
	rerror "set-tankanji-dic: illegal encoding flag \"$eflag\".";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "set-tankanji-dic: $fn: not found or unavailable.";
	return;
      }
      my $r = Naggy::TankanjiDic->new($file, encoding => $e);
      $self->{convert}->{tankanji_dic} = $r;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"delete-tankanji-dic"} = sub {
      my $self = shift;
      if (@_ != 0) {
	rerror "delete-tankanji-dic: illegal arguments.";
	return;
      }
      $self->{convert}->{tankanji_dic} = undef;
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"add-skk-dic"} = sub {
      my $self = shift;
      if (@_ != 1 && @_ != 2) {
	rerror "add-skk-dic: illegal arguments.";
	return;
      }
      my ($fn, $eflag) = @_;
      $eflag = "-u" if ! defined $eflag;
      my $e;
      if ($eflag eq "-e") {
	if ($Resource::USE_JISX0213) {
	  $e = "euc-jisx0213";
	} else {
	  $e = "euc-jp";
	}
      } elsif ($eflag eq "-s") {
	$e = "cp932";
      } elsif ($eflag eq "-u") {
	$e = "utf8";
      } else {
	rerror "add-skk-dic: illegal encoding flag \"$eflag\".";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "add-skk-dic: $fn: not found or unavailable.";
	return;
      }
      my $r = Naggy::SKKDic->new($file, encoding => $e);
      push(@{$self->{convert}->{skk_dics}}, $r);
      rprint "# begin unit\nok\n# end\n";
    };

    $COMMAND{"delete-skk-dic"} = sub {
      my $self = shift;
      if (@_ != 1) {
	rerror "delete-skk-dic: illegal arguments.";
	return;
      }
      my ($fn) = @_;
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	$file = $fn;
      }
      my @r;
      my $done = 0;
      foreach my $d (@{$self->{convert}->{skk_dics}}) {
	if ($d->{filename} eq $file) {
	  $done = 1;
	} else {
	  push(@r, $d);
	}
      }
      if ($done) {
	@{$self->{convert}->{skk_dics}} = @r;
	rprint "# begin unit\nok\n# end\n";
      } else {
	rerror "delete-skk-dic: $fn: not found or already unavailable.";
	return;
      }
    };

    $COMMAND{"convert"} = sub {
      my $self = shift;
      if (@_ != 1) {
	rerror "convert: illegal arguments.";
	return;
      }
      my ($s) = @_;
      my @r = $self->{convert}->convert($s);
      if (@r == 1 && ! defined $r[0]) {
	rprint "# begin list\n";
	rprint "# end\n";
      } elsif (@r == 1 && ! ref $r[0]) {
	rprint "# begin string\n";
	rprint  Naggy::escape_string($r[0]) . "\n";
	rprint "# end\n";
      } else {
	rprint "# begin list\n";
	foreach my $l (@r) {
	  my ($d, $pos, $hlit, $com) = @$l;
	  $com = "" if ! defined $com;
	  $hlit = ($hlit)? "h" : "n";
	  rprint 
	    join(" ", map {Naggy::escape_string($_)} ($d, $pos, $hlit, $com))
	      . "\n";
	}
	rprint "# end\n";
      }
    };

    $COMMAND{"load-init-file"} = sub {
      my $self = shift;
      my ($fn, @argv) = @_;
      if (@_ < 1) {
	rerror "load-init-file: illegal arguments.";
	return;
      }
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "load-init-file: $fn: not found or unavailable.";
	return;
      }
      my $prevargv = $self->{INIT_VAR}->{"ARGV"};
      $self->{INIT_VAR}->{"ARGV"} = join(" ", map {Naggy::escape_string($_)} @argv);
      if ($self->load_init_file($file)) {
	if (exists $self->{INIT_VAR}->{"RESULT"}) {
	  rprint "# begin string\n" . 
	    Naggy::escape_string($self->{INIT_VAR}->{"RESULT"}) . "\n" .
	       "# end\n";
	} else {
	  rerror "load-init-file: no result.";
	}
      } else {
	my $s = $self->{INIT_TAIL};
	rprint $s;
      }
      $self->{INIT_VAR}->{"ARGV"} = $prevargv;
    };

    $COMMAND{"print-init-log"} = sub {
      my $self = shift;
      if (@_ != 0) {
	rerror "print-init-log: illegal arguments.";
	return;
      }
      rprint "# begin list\n";
      foreach my $l (split(/\n/, $self->{INIT_LOG})) {
	rprint Naggy::escape_string($l) . "\n";
      }
      rprint "# end\n";
    };

    $COMMAND{"flush-init-log"} = sub {
      my $self = shift;
      if (@_ != 0) {
	rerror "flush-init-log: illegal arguments.";
	return;
      }
      $self->{INIT_LOG} = "";
      $self->{INIT_TAIL} = "";
      rprint "# begin unit\nOK\n# end\n";
    };

    $COMMAND{"find-path"} = sub {
      my $self = shift;
      my ($file, @path) = @_;
      if (@_ < 2) {
	rerror "find-path: illegal arguments. Usage: find-path file dir1 dir2 ...";
	return;
      }
      my $r;
      if (File::Spec->file_name_is_absolute($file)) {
	$r = $file if -e encode_fn($file);
      } else {
	foreach my $dir (@path) {
	  my $f = File::Spec->catfile($dir, $file);
	  if (-e encode_fn($f)) {
	    $r = $f;
	    last;
	  }
	}
      }

      if (defined $r) {
	rprint "# begin string\n" . Naggy::escape_string($r) . "\n# end\n";
      } else {
	rerror "find-path: $file doesn't exists in the path.";
      }
    };

    $COMMAND{"echo"} = sub {
      my $self = shift;
      my $r = join(" ", map {Naggy::escape_string($_)} @_);
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $COMMAND{"split-e"} = sub {
      my $self = shift;
      if (@_ < 1) {
	rerror "split-e: illegal arguments.";
	return;
      }
      my ($m, @rest) = @_;
      @rest = map {split(/\Q$m\E/s, $_)} @rest;
      my $r = join(" ", map {Naggy::escape_string(Naggy::escape_string($_))} @rest);
#      print join($m, map {Naggy::escape_string(Naggy::escape_string($_))} @rest) . "\n";
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $MINILISP_COMMAND{"echo-e"} = sub {
      my $self = shift;
      my $r = join(" ", map {Naggy::escape_string(Naggy::escape_string($_))} @_);
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $UNSAFE_COMMAND{"concat-filename"} = sub {
      my $self = shift;
      if (@_ < 2) {
	rerror "concat-filename: illegal arguments.";
	return;
      }
      my $r = Naggy::escape_string(File::Spec->catfile(@_));
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $UNSAFE_COMMAND{"split-path-e"} = sub {
      my $self = shift;
      if (@_ != 1 && @_ != 2) {
	rerror "split-path-e: illegal arguments.";
	return;
      }
      my $r = join(" ", map {Naggy::escape_string(Naggy::escape_string($_))} File::Spec->splitpath(@_));
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };
    $UNSAFE_COMMAND{"split-extension-e"} = sub {
      my $self = shift;
      if (@_ != 1) {
	rerror "split-extension-e: illegal arguments.";
	return;
      }
      my ($fn) = @_;
      my $ext = "";
      $ext = $& if $fn =~ s/\.[^\.\/\\]+$//s;
      my $r = join(" ", map {Naggy::escape_string(Naggy::escape_string($_))} ($fn, $ext));
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $MINILISP_COMMAND{"join"} = sub {
      my $self = shift;
      if (@_ < 1) {
	rerror "join: illegal arguments.";
	return;
      }
      my ($d, @rest) = @_;
      my $r = Naggy::escape_string(join($d, @rest));
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    #   $MINILISP_COMMAND{"string-in-string"} = sub {
    #     my $self = shift;
    #     if (@_ < 1) {
    #       rerror "string-in-string: illegal arguments.";
    #       return;
    #     }
    #     my ($q, @rest) = @_;
    #     my $r = 0;
    #     foreach my $s (@rest) {
    #       if ($s =~ /\Q$q\E/s) {
    # 	$r = 1;
    # 	last;
    #       }
    #     }
    #     rprint "# begin string\n";
    #     rprint $r . "\n";
    #     rprint "# end\n";
    #   };
    #   $MINILISP_COMMAND{"escape-e"} = sub {
    #     my $self = shift;
    #     if (@_ < 1) {
    #       rerror "escape-e: illegal arguments.";
    #       return;
    #     }
    #     my ($d, @rest) = @_;
    #     $d =~ s/\\//g;
    #     my @r;
    #     foreach my $s (@rest) {
    #       $s = Naggy::escape_string($s);
    #       if ($d ne "") {
    # 	$s =~ s([[\Q$d\E]){
    # 	  my $c = ord($&);
    # 	  if ($c < 0x80) {
    # 	    sprintf("\\x%02X", $c);
    # 	  } else {
    # 	    sprintf("\\u{%X}", $c);
    # 	  }
    # 	}gsex;
    #       }
    #       push(@r, $s);
    #     }
    #     my $r = join(" ", map {Naggy::escape_string($_)} (@r));
    #     rprint "# begin string\n";
    #     rprint $r . "\n";
    #     rprint "# end\n";
    #   };

    $MINILISP_COMMAND{"add"} = sub {
      my $self = shift;
      if (@_ != 2) {
	rerror "add: illegal arguments.";
	return;
      }
      my ($a, $b) = @_;
      my $r = Naggy::escape_string($a + $b);
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $MINILISP_COMMAND{"list-length"} = sub {
      my $self = shift;
      my $r = Naggy::escape_string(scalar @_);
      rprint "# begin string\n";
      rprint $r . "\n";
      rprint "# end\n";
    };

    $MINILISP_COMMAND{"nth"} = sub {
      my $self = shift;
      if (@_ < 1) {
	rerror "nth: illegal arguments.";
	return;
      }
      my ($num, @rest) = @_;
      if ($num < @rest && $num >= 0) {
	my $r = Naggy::escape_string($rest[$num]);
	rprint "# begin string\n";
	rprint $r . "\n";
	rprint "# end\n";
      } elsif (- $num <= @rest && $num < 0) {
	my $r = Naggy::escape_string($rest[@rest + $num]);
	rprint "# begin string\n";
	rprint $r . "\n";
	rprint "# end\n";
      } else {
	rerror "nth: out of bounds.";
      }
    };

    $MINILISP_COMMAND{"nthcdr-e"} = sub {
      my $self = shift;
      if (@_ < 1) {
	rerror "nthcdr-e: illegal arguments.";
	return;
      }
      my ($num, @rest) = @_;
      if (($num < @rest && $num >= 0) || (- $num <= @rest && $num < 0)) {
	splice(@rest, 0, $num) if $num > 0;
	splice(@rest, 0, @rest + $num) if $num < 0;
	my $r = join(" ", map {Naggy::escape_string(Naggy::escape_string($_))} @rest);
	rprint "# begin string\n";
	rprint $r . "\n";
	rprint "# end\n";
      } else {
	rerror "nthcdr-e: out of bounds.\n";
      }
    };

    # $UNSAFE_COMMAND{"while-not"} = sub {
    #   my $self = shift;
    #   if (@_ < 2) {
    # 	rerror "while-not: illegal arguments.";
    # 	return;
    #   }
    #   my ($var, $content, @argv) = @_;
    #   my $prevargv = $self->{INIT_VAR}->{"ARGV"};
    #   my $argv = join(" ", map {Naggy::escape_string($_)} @argv);
    #   $self->{INIT_VAR}->{"ARGV"} = $argv;
    #   while (! exists $self->{INIT_VAR}->{$var}
    # 	     || ! Naggy::is_true($self->{INIT_VAR}->{$var})) {
    # 	delete $self->{INIT_VAR}->{"RESULT"};
    # 	#      $self->{INIT_VAR}->{"ARGV"} = $argv;
    # 	if (! $self->load_init_file_from_string($content)) {
    # 	  rprint $self->{INIT_TAIL};
    # 	  $self->{INIT_VAR}->{"ARGV"} = $prevargv;
    # 	  return;
    # 	}
    #   }
    #   if (exists $self->{INIT_VAR}->{"RESULT"}) {
    # 	rprint "# begin string\n" . 
    # 	  Naggy::escape_string($self->{INIT_VAR}->{"RESULT"}) . "\n" .
    # 	     "# end\n";
    #   } else {
    # 	rerror "while-not: no result.";
    #   }
    # };

    ## "while-not" causes well-known problems about "EVAL", that's why
    ## it's UNSAFE. But when UNSAFE, you can write $content into a
    ## temporary file and call it by "load-init-file-while-not".  If
    ## you can control locate_file_resouce to prohibit users'
    ## programs, it makes sense, uncomment above.

    $MINILISP_COMMAND{"load-init-file-while-not"} = sub {
      my $self = shift;
      if (@_ < 2) {
	rerror "load-init-file-while-not: illegal arguments.";
	return;
      }

      my ($var, $fn, @argv) = @_;
      my $file = locate_file_resource($fn);
      if (! defined $file) {
	rerror "load-init-file-while-not: $fn: not found or unavailable.";
	return;
      }
      my $prevargv = $self->{INIT_VAR}->{"ARGV"};
      my $argv = join(" ", map {Naggy::escape_string($_)} @argv);
      $self->{INIT_VAR}->{"ARGV"} = $argv;
      while (! exists $self->{INIT_VAR}->{$var}
	     || ! Naggy::is_true($self->{INIT_VAR}->{$var})) {
	delete $self->{INIT_VAR}->{"RESULT"};
	#      $self->{INIT_VAR}->{"ARGV"} = $argv;
	if (! $self->load_init_file($file)) {
	  my $s = $self->{INIT_TAIL};
	  rprint $s;
	  $self->{INIT_VAR}->{"ARGV"} = $prevargv;
	  return;
	}
      }
      if (exists $self->{INIT_VAR}->{"RESULT"}) {
	rprint "# begin string\n" . 
	  Naggy::escape_string($self->{INIT_VAR}->{"RESULT"}) . "\n" .
	     "# end\n";
      } else {
	rerror "load-init-file-while-not: no result.";
      }
    };

    $UNSAFE_COMMAND{"read-with-encoding-e"} = sub {
      my $self = shift;
      if (@_ != 2) {
	rerror "read-with-encoding-e: illegal arguments.";
	return;
      }
      my ($file, $enc) = @_;
      my $ret;

      if ($enc =~ s/-crlf$//i || $enc =~ s/-dos$//i) {
	$ret = "\x0d\x0a";
      } elsif ($enc =~ s/-unix$//i) {
	$ret = "\x0a";
      }
      my $r = "";
      my $fh;
      if ($file eq "") {
	open($fh, "<&STDIN");
      } else {
	if (open($fh, "<", encode_fn($file))) {
	  rerror "read-with-encoding-e: $file: $!.";
	  return;
	}
      }
      binmode($fh, ":raw");
      if (lc($enc) eq "raw" || lc($enc) eq "binary") {
	$r = Naggy::escape_string(Naggy::escape_string(join("", <$fh>)));
      } else {
	$enc = Encode::find_encoding($enc);
	if (! defined $enc) {
	  rerror "read-with-encoding-e: no such encoding.";
	  close($fh);
	  return;
	}
	while (<$fh>) {
	  if (defined $ret) {
	    s/\Q$ret\E$//s;
	  } else {
	    s/\x0a$//s;
	    s/\x0d$//s;
	  }
	  $_ = $enc->decode($_);
	  $r .= Naggy::escape_string(Naggy::escape_string($_)) . "\n";
	}
      }
      close($fh);
      rprint "# begin list\n$r\n# end\n";
    };

    $UNSAFE_COMMAND{"write-with-encoding"} = sub {
      my $self = shift;
      if (@_ < 2) {
	rerror "write-with-encoding: illegal arguments.";
	return;
      }
      my ($file, $enc, @l) = @_;
      my $ret = "\x0a";

      if ($enc =~ s/-crlf$//i || $enc =~ s/-dos$//i) {
	$ret = "\x0d\x0a";
      } elsif ($enc =~ s/-unix$//i) {
	$ret = "\x0a";
      }
      if (lc($enc) ne "binary" && lc($enc) ne "raw") { 
	$enc = Encode::find_encoding($enc);
	if (! defined $enc) {
	  rerror "write-with-encoding: no such encoding.";
	  return;
	}
      }
      my $r = "";
      my $fh;
      if ($file eq "") {
	open($fh, ">&STDIN");
      } else {
	if (! open($fh, ">", encode_fn($file))) {
	  rerror "write-with-encoding: $file: $!.";
	  return;
	}
      }
      binmode($fh, ":raw");
      if (lc($enc) eq "raw" || lc($enc) eq "binary") {
	foreach my $l (@l) {
	  print $fh $l;
	}
      } else {
	foreach my $l (@l) {
	  print $fh ($l . $ret);
	}
      }
      close($fh);
      rprint "# begin unit\nok\n# end\n";
    };

    $UNSAFE_COMMAND{"set-filename-encoding"} = sub {
      my $self = shift;
      my ($s) = @_;
      if (@_ != 1) {
	rerror "set-filename-encoding: illegal arguments.";
	return;
      }
      my $enc = Encode::find_encoding($s);
      if (defined $enc) {
	$Resource::FILENAME_ENCODING = $s;
	rprint "# begin unit\nok\n# end\n";
      } else {
	rerror "set-filename-encoding: No such encoding.";
      }
    };

    $COMMAND{"list-command"} = sub {
      my $self = shift;
      if (@_ != 0) {
	rerror "list-command: illegal arguments.";
	return;
      }
      rprint "# begin list\n";
      foreach my $k (sort keys %{$self->{command}}) {
	rprint Naggy::escape_string($k) . "\n";
      }
      rprint "# end\n";
    };

    $COMMAND{"list-commands"} = $COMMAND{"list-command"};
  }
}

{
  package Naggy::Backend::Command;
  use base qw(JRF::MyOO);
  our $VERSION = $Naggy::Backend::VERSION;

  use IO::Handle;
  use Pod::Usage;
  use Getopt::Long qw();
  use File::Spec::Functions qw(catfile);
  use JRF::Resource;
  use JRF::Utils qw(:all);
  use Naggy;

  __PACKAGE__->extend_template
    (
     init_file => undef,
     batch_mode => undef,
     backend => undef,
    );

  sub process_arguments {
    my $self = shift;
    my @args = @_;
    my @init_var;
    my $translit;
    my $init_file;
    my $fwperiod = 0;
    my $unsafe = 0;

    Getopt::Long::Configure("posix_default", "auto_version",
			    "no_ignore_case", "gnu_compat");
    Getopt::Long::GetOptionsFromArray
       (\@args,
	"console-encoding=s" => \$Resource::CONSOLE_ENCODING,
	"filename-encoding=s" => \$Resource::FILENAME_ENCODING,
	"D|define=s@"  => \@init_var,
	"I=s" => sub { my ($n, $v) = @_;
		       unshift(@Resource::RESOURCE_PATH, decode_con($v)); },
	"input-file=s" => \$init_file,
	"translit=s"  => \$translit,
	"unsafe-init"  => \$unsafe,
	"punctuation-fullwidth-period" => \$fwperiod,
        "jisx0213" => \$Resource::USE_JISX0213,
	"man" => sub {pod2usage(-verbose => 2)},
	"h|?" => sub {pod2usage(-verbose => 0, -output=>\*STDOUT, 
				-exitval => 1)},
	"help" => sub {pod2usage(1)},
       ) or pod2usage(-verbose => 0);
    for (my $i = 0; $i < @args; $i++) {
      $args[$i] = decode_con($args[$i]);
    }

    $self->{init_file} = decode_con($init_file) if defined $init_file;

    my $ngb = Naggy::Backend->new(UNSAFE => decode_con($unsafe),
				  PUNCTUATION_FULLWIDTH_PERIOD => decode_con($fwperiod));
    $self->{backend} = $ngb;

    $ngb->{INIT_VAR}->{"ARGV"}
      = join(" ", map {Naggy::escape_string($_)} @args);
    foreach my $kv (@init_var) {
      my ($k, $v) = split(/[= ]/, decode_con($kv), 2);
      $ngb->{INIT_VAR}->{$k} = $v;
    }
    $ngb->{BATCH_MODE} = ["translit", decode_con($translit)]
      if defined $translit;
  }

  sub command_loop {
    my $self = shift;
    my $ngb = $self->{backend};

    STDOUT->autoflush(1) if ! defined $ngb->{BATCH_MODE};
    binmode(STDOUT, ":unix:utf8");
    binmode(STDERR, ":unix:utf8");
    binmode(STDIN, ":unix:utf8");

    $SIG{__WARN__} = \&Naggy::Backend::rwarn;

    if (defined $self->{init_file}) {
      $ngb->load_init_file($self->{init_file})
	or die $ngb->{INIT_TAIL} . "\n";
    } else {
      my $fn;
      $fn = locate_file_resource(catfile($ENV{HOME}, ".naggy-backend"));
      if (! defined $fn) {
	$fn = locate_file_resource("site-init.nginit");
      }
      if (defined $fn) {
	$ngb->load_init_file($fn)
	  or die $ngb->{INIT_TAIL} . "\n";
      }
    }

    if (defined $ngb->{BATCH_MODE}) {
      my @argv = map {Naggy::unescape_string($_)}
	split(/\s+/, $ngb->{INIT_VAR}->{"ARGV"});
      my ($cmd, @args) = (@{$ngb->{BATCH_MODE}}, @argv);
      if ($cmd eq "translit") {
	my $translit = $ngb->{translit};
	if (@args != 2 && @args != 1 ) {
	  die "# error Illegal arguments.\n";
	}
	my ($spec, $file) = @args;
	if (! exists $translit->{table}->{$spec}) {
	  die "# error No such translit table: $spec.\n";
	}
	my $fh;
	if (defined $file) {
	  open($fh, "<", encode_fn($file))
	    or die "# error $file: $!\n";
	} else {
	  open($fh, "<&STDIN") or die "# error STDIN: $!\n";
	}
	binmode($fh, ":utf8");
	while (<$fh>) {
	  s/\x0a$//s;
	  s/\x0d$//s;
	  s(\S+){
	    $translit->translit($spec, $&);
	  }gsex;
	  print $_ . "\n";
	}
	close($fh);
      }
      exit(0);
    }

    while (<STDIN>) {
      chomp;
      my ($cmd, @args) = map {Naggy::unescape_string($_)} split(/\s+/, $_);
      $cmd = "nop" if ! defined $cmd;
      $ngb->process_command($cmd, @args);
    }
  }

  sub new {
    my $class = shift;
    my $obj =  $class->SUPER::new(@_);
    $obj->process_arguments(@_);
    return $obj;
  }
}

1;
