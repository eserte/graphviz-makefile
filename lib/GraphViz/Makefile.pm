# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2002,2003,2005,2008,2013,2020 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: srezic@cpan.org
# WWW:  http://www.rezic.de/eserte/
#

package GraphViz::Makefile;
use GraphViz;
use Make;
use strict;
use warnings;

our $VERSION = '1.18';

our $V = 0 unless defined $V;
my @ALLOWED_ARGS = qw(reversed);
my %ALLOWED_ARGS = map {($_,undef)} @ALLOWED_ARGS;

our %NodeStyleTarget = (
    shape     => 'box',
    style     => 'filled',
    fillcolor => '#ffff99',
    fontname  => 'Arial',
    fontsize  => 10,
);
our %NodeStyleRecipe = (
    shape     => 'note',
    style     => 'filled',
    fillcolor => '#dddddd',
    fontname  => 'Monospace',
    fontsize  => 8,
);

sub new {
    my ($pkg, $g, $make, $prefix, %args) = @_;
    if (!$make) {
        $make = Make->new;
    } elsif (!UNIVERSAL::isa($make, "Make")) {
        my $makefile = $make;
        $make = Make->new;
        $make->parse($makefile);
    }

    my @illegal_args = grep !exists $ALLOWED_ARGS{$_}, keys %args;
    die "Unrecognized arguments @illegal_args, known arguments are @ALLOWED_ARGS"
        if @illegal_args;

    my $self = { GraphViz => $g,
                 Make     => $make,
                 Prefix   => ($prefix||""),
                 %args
               };
    bless $self, $pkg;
}

sub GraphViz { shift->{GraphViz} ||= GraphViz->new }
sub Make     { shift->{Make}     }

sub generate {
    my ($self, $target) = @_;
    $target = "all" if !defined $target;
    my ($nodes, $edges) = $self->generate_tree($self->{Make}->expand($target));
    my $g = $self->GraphViz;
    $g->add_node($_, %{ $nodes->{$_} }) for keys %$nodes;
    for my $edge_start (keys %$edges) {
        my $sub_edges = $edges->{$edge_start};
        $g->add_edge($edge_start, $_, @{ $sub_edges->{$_} }) for keys %$sub_edges;
    }
}

my ($id_counter, %ref2counter);
sub _gen_id {
    my ($ref) = @_;
    $ref2counter{$ref} ||= ++$id_counter;
    ':recipe:' . $ref2counter{$ref}; # needs to be unique to that recipe
}
sub _reset_id {
    undef %ref2counter;
    $id_counter = 0;
}

# mutates $nodes and $edges
sub generate_tree {
    my ($self, $target, $visited, $nodes, $edges) = @_;
    $visited ||= {};
    $nodes ||= {};
    $edges ||= {};
    return if $visited->{$target}++;
    if (!$self->{Make}->has_target($target)) {
        warn "Can't get make target for $target\n" if $V;
        return;
    }
    my $prefix = $self->{Prefix};
    $nodes->{$prefix.$target} ||= \%NodeStyleTarget;
    my $make_target = $self->{Make}->target($target);
    my ($recipe_rules, $bare_rules) = _rules_partition($make_target);
    my @merged_rules = _rules_merge($recipe_rules, $bare_rules);
    if (!@merged_rules and !@$bare_rules) {
        warn "No depends for target $target\n" if $V;
        return;
    }
    my %to_visit;
    if (@merged_rules) {
        for my $recipe_rule (@merged_rules) {
            my $recipe_id = _gen_id($recipe_rule->{recipe});
            my $recipe_label = join '', map "$_\\l", @{ $recipe_rule->{recipe} };
            $recipe_label =~ s/"/\\"/g; # GraphViz.pm quoting is broken
            $nodes->{$recipe_id} ||= { %NodeStyleRecipe, label => $recipe_label };
            my @recipe_edge = ($prefix.$target, $recipe_id);
            @recipe_edge = reverse @recipe_edge if $self->{reversed};
            $edges->{$recipe_edge[0]}{$recipe_edge[1]} ||= [];
            warn "$recipe_edge[0] => $recipe_edge[1]\n" if $V >= 2;
            for my $dep (@{ $recipe_rule->{prereqs} }) {
                $nodes->{$prefix.$dep} ||= \%NodeStyleTarget;
                my @edge = ($recipe_id, $prefix.$dep);
                @edge = reverse @edge if $self->{reversed};
                $edges->{$edge[0]}{$edge[1]} ||= [];
                warn "$edge[0] => $edge[1]\n" if $V >= 2;
                $to_visit{$dep}++;
            }
        }
    } else {
        for my $bare_rule (@$bare_rules) {
            for my $dep (@{ $bare_rule->prereqs }) {
                $nodes->{$prefix.$dep} ||= \%NodeStyleTarget;
                my @edge = ($prefix.$target, $prefix.$dep);
                @edge = reverse @edge if $self->{reversed};
                $edges->{$edge[0]}{$edge[1]} ||= [];
                warn "$edge[0] => $edge[1]\n" if $V >= 2;
                $to_visit{$dep}++;
            }
        }
    }
    $self->generate_tree($_, $visited, $nodes, $edges) for sort keys %to_visit;
    ($nodes, $edges);
}

sub find_recursive_makes {
    my ($self, $target_name, $cmd) = @_;
    if (defined $cmd && $cmd =~ /\bcd\s+(\w+)\s*(?:;|&&)\s*make\s*(.*)/) {
        my ($dir, $makeargs) = ($1, $2);
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
#        warn "dir: $dir, file: $makefile, rule: $rule\n";
        my $f = "$dir/$makefile"; # XXX make better. use $make->{GNU}
        $f = "$dir/Makefile" if !-r $f;
        my $gm2 = GraphViz::Makefile->new($self->GraphViz, $f, "$dir/"); # XXX save_pwd verwenden; -f option auswerten
        $gm2->generate($rule);
        $self->GraphViz->add_edge($target_name, "$dir/$rule");
    } else {
        warn "can't match external make command in $cmd\n" if $V;
    }
}

sub _rules_partition {
    my ($make_target) = @_;
    my @rules = @{ $make_target->rules };
    my (@recipe_rules, @bare_rules);
    push @{ @{$_->recipe} ? \@recipe_rules : \@bare_rules }, $_ for @rules;
    (\@recipe_rules, \@bare_rules);
}

sub _rules_merge {
    my ($recipe_rules, $bare_rules) = @_;
    my @bare_deps = map @{ $_->prereqs }, @$bare_rules;
    map +{ recipe => $_->recipe, prereqs => [ @{ $_->prereqs }, @bare_deps ] },
        @$recipe_rules;
}

1;


__END__

=head1 NAME

GraphViz::Makefile - Create Makefile graphs using GraphViz

=head1 SYNOPSIS

Output to a .png file:

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    my $g = GraphViz->new;
    my ($nodes, $edges) = $gm->generate_tree("all"); # or another makefile target
    $g->add_node($_, %{ $nodes->{$_} }) for keys %$nodes;
    for my $edge_start (keys %$edges) {
        my $sub_edges = $edges->{$edge_start};
        $g->add_edge($edge_start, $_, @{ $sub_edges->{$_} }) for keys %$sub_edges;
    }
    $g->as_png("makefile.png");

To output to a .ps file, just replace C<png> with C<ps> in the filename
and method above.

Or, using the deprecated mutation style:

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    $gm->generate("all"); # or another makefile target
    $gm->GraphViz->as_png("makefile.png");

=head1 DESCRIPTION

B<GraphViz::Makefile> uses the L<GraphViz> and L<Make> modules to
visualize Makefile dependencies.

=head2 METHODS

=over

=item new($graphviz, $makefile, $prefix, %args)

Create a C<GraphViz::Makefile> object. The first argument should be a
C<GraphViz> object or C<undef>. In the latter case, a new C<GraphViz>
object is created by the constructor. The second argument should be a
C<Make> object, the filename of a Makefile, or C<undef>. In the latter
case, the default Makefile is used. The third argument C<$prefix> is
optional and can be used to prepend a prefix to all rule names in the
graph output.

The created nodes are named C<rule_$prefix$name>.

Further arguments (specified as key-value pairs):

=over

=item reversed => 1

Point arrows in the direction of dependencies. If not set, then the
arrows point in the direction of "build flow".

=back

=item generate($rule)

Generate the graph, beginning at the named Makefile rule. If C<$rule>
is not given, C<all> is used instead. Mutates the internal C<GraphViz>
object.

=item find_recursive_makes($target_name, $cmd)

Search the command for a recursive make (change directory, call
make). Incorporates into this graph with the subdirectory's target as
C<dirname/targetname>.

=item generate_tree($target)

    my ($nodes, $edges) = $gm->generate_tree("all"); # or another makefile target
    $g->add_node($_, %{ $nodes->{$_} }) for keys %$nodes;
    for my $edge_start (keys %$edges) {
        my $sub_edges = $edges->{$edge_start};
        $g->add_edge($edge_start, $_, @{ $sub_edges->{$_} }) for keys %$sub_edges;
    }

Return a hash-refs of nodes and edges. The values (or second-level
values for edges) are array-refs of further arguments for the GraphViz
C<add_node> and C<add_edge> methods respectively.

=item GraphViz

Return a reference to the C<GraphViz> object. This object will be used
for the output methods. Will only be created if used. It is recommended
to instead use the C<generate_tree> method and make the calls on an
externally-controlled L<GraphViz> object.

=item Make

Return a reference to the C<Make> object.
 
=back

=head2 ALTERNATIVES

There's another module doing the same thing: L<Makefile::GraphViz>.

=head1 AUTHOR

Slaven Rezic <srezic@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2002,2003,2005,2008,2013 Slaven Rezic. All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<GraphViz>, L<Make>, L<make(1)>, L<tkgvizmakefile>.

=cut
