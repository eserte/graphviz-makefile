#!/usr/bin/perl -w
# -*- perl -*-

#
# $Id: Makefile.pm,v 1.5 2002/03/11 23:51:38 eserte Exp $
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

my $V = 1;

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
warn "$prefix$target => $prefix$dep\n";
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

	warn "dir: $dir, file: $makefile, rule: $rule\n";
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
package Make;

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
#warn "key=$key var=$var op=$op vars=@var\n";
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

package GraphViz;

sub as_tk_canvas {
    my($self, $c) = @_;
    GraphViz::TkCanvas::graphviz($c, $self->as_plain);
}

package GraphViz::TkCanvas;
use Text::ParseWords;
sub graphviz {
    my($c, $text) = @_;

    my $tfm = sub { my($x,$y) = @_; ($x*100,$y*100) };
    foreach my $l (split /\n/, $text) {
	my(@w) = shellwords($l);
	if ($w[0] eq 'graph') {
	    $c->configure(-scrollregion => [$tfm->(0,0),$tfm->($w[2],$w[3])]);
	} elsif ($w[0] eq 'node') {
	    my($x,$y) = $tfm->($w[2],$w[3]);
	    my($w,$h) = $tfm->($w[4],$w[5]);
	    my $text = $w[6];
	    $c->createOval($x-$w/2,$y-$h/2,$x+$w/2,$y+$h/2, -fill=>"gray");
	    $c->createText($x,$y,-text => $text, -tag => ["rule","rule_$text"]);
	} elsif ($w[0] eq 'edge') {
	    my $no = $w[3];
	    my @coords;
	    for(my $i=0; $i<$no*2; $i+=2) {
		push @coords, $tfm->($w[4+$i], $w[5+$i]);
	    }
	    $c->createLine(@coords, -arrow => "last", -smooth => 1);
	} else {
	    warn "?@w\n";
	}
    }
}

package main;

$ENV{MAKE}="make";
use Getopt::Long;
my $file = "Makefile";
GetOptions("f|file=s" => \$file) or die;
use Tk;
use lib "/home/e/eserte/src/bbbike/lib";
use Tk::CanvasUtil;
my $mw = new MainWindow;
my $c = $mw->Scrolled("Canvas")->pack(-fill=>"both",-expand=>1);
my $rule = shift || "all";
my $gm = GraphViz::Makefile->new(undef, $file);
$gm->generate($rule);
#open(O, ">/tmp/bla.fig") or die $!;
#binmode O;
#print O
 $gm->{GraphViz}->as_tk_canvas($c);

my @c = $c->coords("rule_$rule");
$c->see($c[0],$c[1]);
#  $c->bind("rule", "<1>" => sub {
#  	     my $c = shift;
#  	     my $file = ($c->gettags("current"))[1];
#  	     if (is_in_path("emacsclient")) {
#  		 system('emacsclient', '--no-wait', $file);
#  	     }
#  	 });

#close O;

MainLoop;

# REPO BEGIN
# REPO NAME is_in_path /home/e/eserte/src/repository 
# REPO MD5 1b42243230d92021e6c361e37c9771d1

=head2 is_in_path($prog)

=for category File

Return the pathname of $prog, if the program is in the PATH, or undef
otherwise.

DEPENDENCY: file_name_is_absolute

=cut

sub is_in_path {
    my($prog) = @_;
    return $prog if (file_name_is_absolute($prog) and -f $prog and -x $prog);
    require Config;
    my $sep = $Config::Config{'path_sep'} || ':';
    foreach (split(/$sep/o, $ENV{PATH})) {
	if ($^O eq 'MSWin32') {
	    return "$_\\$prog"
		if (-x "$_\\$prog.bat" ||
		    -x "$_\\$prog.com" ||
		    -x "$_\\$prog.exe");
	} else {
	    return "$_/$prog" if (-x "$_/$prog");
	}
    }
    undef;
}
# REPO END

# REPO BEGIN
# REPO NAME file_name_is_absolute /home/e/eserte/src/repository 
# REPO MD5 a77759517bc00f13c52bb91d861d07d0

=head2 file_name_is_absolute($file)

=for category File

Return true, if supplied file name is absolute. This is only necessary
for older perls where File::Spec is not part of the system.

=cut

sub file_name_is_absolute {
    my $file = shift;
    my $r;
    eval {
        require File::Spec;
        $r = File::Spec->file_name_is_absolute($file);
    };
    if ($@) {
	if ($^O eq 'MSWin32') {
	    $r = ($file =~ m;^([a-z]:(/|\\)|\\\\|//);i);
	} else {
	    $r = ($file =~ m|^/|);
	}
    }
    $r;
}
# REPO END

