#!/usr/bin/perl -w
# -*- perl -*-

#
# $Id: Makefile.pm,v 1.1 2002/03/06 01:19:19 eserte Exp $
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
    if (!$make_target->colon) {
	$seen{$target}++;
	warn "No colon for target $target";
	return;
    }
    my @depends = $make_target->colon->depend;
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

package main;

my $gm = GraphViz::Makefile->new(undef, "Makefile");
$gm->generate;
open(O, ">/tmp/bla.ps") or die $!;
binmode O;
print O $gm->{GraphViz}->as_ps;
close O;
