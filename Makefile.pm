# -*- perl -*-

#
# $Id: Makefile.pm,v 1.8 2002/03/18 14:12:38 eserte Exp $
# Author: Slaven Rezic
#
# Copyright (C) 2002 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven.rezic@berlin.de
# WWW:  http://www.rezic.de/eserte/
#

package GraphViz::Makefile;
use GraphViz;
use Make;
use strict;

use vars qw($VERSION $V);
$VERSION = sprintf("%d.%02d", q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/);

$V = 1 unless defined $V;

sub new {
    my($pkg, $g, $make, $prefix) = @_;
    $g = GraphViz->new unless $g;
    if (!$make) {
	$make = Make->new;
    } elsif (!UNIVERSAL::isa($make, "Make")) {
	$make = Make->new(Makefile => $make);
    }
    my $self = { GraphViz => $g,
		 Make     => $make,
		 Prefix   => ($prefix||""),
	       };
    bless $self, $pkg;
}

sub generate {
    my($self, $target) = @_;
    $target = "all" if !defined $target;
    my $seen = {};
    $self->_generate($target, $seen);
}

sub _generate {
    my($self, $target, $seen) = @_;
    return if $seen->{$target};
    my $make_target = $self->{Make}->Target($target);
    if (!$make_target) {
	warn "Can't get make target for $target\n" if $V;
	$seen->{$target}++;
	return;
    }
    my @depends = $self->_all_depends($self->{Make}, $make_target);
    if (!@depends) {
	$seen->{$target}++;
	warn "No depends for target $target\n" if $V;
	return;
    }
    my $g = $self->{GraphViz};
    my $prefix = $self->{Prefix};
    $g->add_node("$prefix$target");
    foreach my $dep (@depends) {
	$g->add_node("$prefix$dep") unless $seen->{$dep};
	$g->add_edge("$prefix$target", "$prefix$dep");
#warn "$prefix$target => $prefix$dep\n";
    }
    $seen->{$target}++;
    foreach my $dep (@depends) {
	$self->_generate($dep, $seen);
    }
}

sub guess_external_makes {
    my($self, $make_rule, $cmd) = @_;
    if ($cmd =~ /\bcd\s+(\w+)\s*(?:;|&&)\s*make\s*(.*)/) {
	my($dir, $makeargs) = ($1, $2);
	my $makefile;
	my $rule;
	{
	    require Getopt::Long;
	    local @ARGV = split /\s+/, $makeargs;
	    $makefile = "makefile";
	    # XXX parse more options
	    Getopt::Long::GetOptions("f=s" => \$makefile);
	    my @env;
	    foreach (@ARGV) {
		if (!defined $rule) {
		    $rule = $_;
		} elsif (/=/) {
		    push @env, $_;
		}
	    }
	}

#	warn "dir: $dir, file: $makefile, rule: $rule\n";
	my $f = "$dir/$makefile"; # XXX make better. use $make->{GNU}
	$f = "$dir/Makefile" if !-r $f;
	my $gm2 = GraphViz::Makefile->new($self->{GraphViz}, $f, "$dir/"); # XXX save_pwd verwenden; -f option auswerten
	$gm2->generate($rule);

	$self->{GraphViz}->add_edge($make_rule->Name, "$dir/$rule");
    } else {
	warn "can't match external make command in $cmd\n";
    }
}

sub _all_depends {
    my($self, $make, $make_target) = @_;
    my @depends;
    if ($make_target->colon) {
#	push @depends, $make_target->colon->depend;
	push @depends, $make_target->colon->exp_depend;
	$self->guess_external_makes($make_target, $make_target->colon->exp_command);
    } elsif ($make_target->dcolon) {
	foreach my $rule ($make_target->dcolon) {
	    #push @depends, $rule->depend;
	    push @depends, $rule->exp_depend;
	    $self->guess_external_makes($rule, $rule->exp_command);
	}
    }
#    map { split(/\s+/,$make->subsvars($_)) } @depends;
    @depends;
}

{
package
    Make;

sub subsvars
{
 my $self = shift;
 local $_ = shift;
 my @var = @_;
 push(@var,$self->{Override},$self->{Vars},\%ENV);
 croak("Trying to subsitute undef value") unless (defined $_); 
 while (/(?<!\$)\$\(([^()]+)\)/ || /(?<!\$)\$([<\@^?*])/)
  {
   my ($key,$head,$tail) = ($1,$`,$');
   my $value;
   if ($key =~ /^([\w._]+|\S)(?::(.*))?$/)
    {
     my ($var,$op) = ($1,$2);
     foreach my $hash (@var)
      {
       $value = $hash->{$var};
       if (defined $value)
        {
         last; 
        }
      }
     unless (defined $value)
      {
#XXX $@ not defined?
#XXX       die "$var not defined in '$_'" unless (length($var) > 1); 
       $value = '';
      }
     if (defined $op)
      {
       if ($op =~ /^s(.).*\1.*\1/)
        {
         local $_ = $self->subsvars($value);
         $op =~ s/\\/\\\\/g;
         eval $op.'g';
         $value = $_;
        }
       else
        {
         die "$var:$op = '$value'\n"; 
        }   
      }
    }
   elsif ($key =~ /wildcard\s*(.*)$/)
    {
     $value = join(' ',glob($self->pathname($1)));
    }
   elsif ($key =~ /shell\s*(.*)$/)
    {
     $value = join(' ',split('\n',`$1`));
    }
   elsif ($key =~ /addprefix\s*([^,]*),(.*)$/)
    {
     $value = join(' ',map($1 . $_,split('\s+',$2)));
    }
   elsif ($key =~ /notdir\s*(.*)$/)
    {
     my @files = split(/\s+/,$1);
     foreach (@files)
      {
       s#^.*/([^/]*)$#$1#;
      }
     $value = join(' ',@files);
    }
   elsif ($key =~ /dir\s*(.*)$/)
    {
     my @files = split(/\s+/,$1);
     foreach (@files)
      {
       s#^(.*)/[^/]*$#$1#;
      }
     $value = join(' ',@files);
    }
   elsif ($key =~ /^subst\s+([^,]*),([^,]*),(.*)$/)
    {
     my ($a,$b) = ($1,$2);
     $value = $3;
     $a =~ s/\./\\./;
     $value =~ s/$a/$b/; 
    }
   elsif ($key =~ /^mktmp,(\S+)\s*(.*)$/)
    {
     my ($file,$content) = ($1,$2);
     open(TMP,">$file") || die "Cannot open $file:$!";
     $content =~ s/\\n//g;
     print TMP $content;
     close(TMP);
     $value = $file;
    }
   else
    {
     warn "Cannot evaluate '$key' in '$_'\n";
    }
   $_ = "$head$value$tail";
  }
 s/\$\$/\$/g;
 return $_;
}
}

1;
