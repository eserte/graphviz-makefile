# -*- perl -*-

#
# $Id: Makefile.pm,v 1.11 2003/01/31 11:27:58 eserte Exp $
# Author: Slaven Rezic
#
# Copyright (C) 2002,2003 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package GraphViz::Makefile;
use GraphViz;
use Make;
use strict;

use vars qw($VERSION $V);
$VERSION = sprintf("%d.%02d", q$Revision: 1.11 $ =~ /(\d+)\.(\d+)/);

$V = 0 unless defined $V;

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
	warn "can't match external make command in $cmd\n" if $V;
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
local $^W = 0; # no redefine warnings
package
    Make;

*subsvars = sub
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


__END__

=head1 NAME

GraphViz::Makefile - Create Makefile graphs using GraphViz

=head1 SYNOPSIS

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    $gm->generate("makefile-rule");
    open(O, ">makefile.ps") or die $!;
    binmode O;
    print $gm->{GraphViz}->as_ps;
    close O;

=head1 DESCRIPTION

=head2 METHODS

=over

=item new($graphviz, $makefile, $prefix)

Create a C<GraphViz::Makefile> object. The first argument should be a
C<GraphViz> object or C<undef>. In the latter case, a new C<GraphViz>
object is created by the constructor. The second argument should be a
C<Make> object, the filename of a Makefile, or C<undef>. In the latter
case, the default Makefile is used. The third argument C<$prefix> is
optional and can be used to prepend a prefix to all rule names in the
graph output.

=item generate($rule)

Generate the graph, beginning at the named Makefile rule. If C<$rule>
is not given, C<all> is used instead.

=back

=head2 MEMBERS

The C<GraphViz::Makefile> object is hash-base with the following
public members:

=over

=item GraphViz

A reference to the C<GraphViz> object. This object can be used for the
output methods.

=item Make

A reference to the C<Make> object.

=back

=head1 AUTHOR

Slaven Rezic <srezic@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2002,2003 Slaven Rezic. All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

GraphViz(3), Make(3), make(1).

=cut
