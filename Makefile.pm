#!/usr/bin/perl -w
# -*- perl -*-

#
# $Id: Makefile.pm,v 1.3 2002/03/06 20:38:22 eserte Exp $
# Author: Slaven Rezic
#
# Copyright (C) 2002 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven.rezic@berlin.de
# WWW:  http://www.rezic.de/eserte/
#

# TODO: multiple makefiles, includes...

package GraphViz::Makefile;
use GraphViz;
use Make;

sub new {
    my($pkg, $g, $make) = @_;
    $g = GraphViz->new unless $g;
    if (!$make) {
	$make = Make->new;
    } elsif (!UNIVERSAL::isa($make, "Make")) {
	$make = Make->new(Makefile => $make);
    }
    bless { GraphViz => $g,
	    Make     => $make
	  };
}

sub generate {
    my($self, $target) = @_;
    $target = "all" if !defined $target;
    my $seen = {};
    $self->_generate($target, $seen);
}

sub _generate {
    my($self, $target, $seen) = @_;
    return if $seen{$target};
    my $make_target = $self->{Make}->Target($target);
    if (!$make_target) {
	warn "Can't get make target for $target";
	$seen{$target}++;
	return;
    }
    my @depends = _all_depends($self->{Make}, $make_target);
    if (!@depends) {
	$seen{$target}++;
	warn "No depends for target $target";
	return;
    }
    my $g = $self->{GraphViz};
    $g->add_node($target);
    foreach my $dep (@depends) {
	$g->add_node($dep) unless $seen{$dep};
	$g->add_edge($target, $dep);
    }
    $seen{$target}++;
    foreach my $dep (@depends) {
	$self->_generate($dep, $seen);
    }
}

sub _all_depends {
    my($make, $make_target) = @_;
    my @depends;
    if ($make_target->colon) {
	push @depends, $make_target->colon->depend;
    } elsif ($make_target->dcolon) {
	foreach my $rule ($make_target->dcolon) {
	    push @depends, $rule->depend;
	}
    }
    map { split(/\s+/,$make->subsvars($_)) } @depends;
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
	    $c->createOval($x-$w/2,$y-$h/2,$x+$w/2,$y+$h/2);
	    $c->createText($x,$y,-text => $text);
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

use Getopt::Long;
my $file = "Makefile";
GetOptions("f|file=s" => \$file) or die;
use Tk;
my $mw = new MainWindow;
my $c = $mw->Scrolled("Canvas")->pack(-fill=>"both",-expand=>1);
my $rule = shift || "all";
my $gm = GraphViz::Makefile->new(undef, $file);
$gm->generate($rule);
#open(O, ">/tmp/bla.fig") or die $!;
#binmode O;
#print O
 $gm->{GraphViz}->as_tk_canvas($c);
#close O;

MainLoop;
