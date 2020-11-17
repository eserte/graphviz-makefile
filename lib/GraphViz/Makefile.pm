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
use GraphViz2;
use Make;
use strict;
use warnings;
use Graph;

our $VERSION = '1.18';

our $V = 0 unless defined $V;
my @ALLOWED_ARGS = qw();
my %ALLOWED_ARGS = map {($_,undef)} @ALLOWED_ARGS;
my @RECMAKE_FINDS = (
    \&_find_recmake_cd,
);

our %NodeStyleTarget = (
    shape     => 'box',
    style     => 'filled',
    fillcolor => '#ffff99',
    fontname  => 'Arial',
    fontsize  => 10,
);
our %NodeStyleRecipe = (
    shape     => 'record',
    style     => 'filled',
    fillcolor => '#dddddd',
    fontname  => 'Monospace',
    fontsize  => 8,
);
our %NodeStyleRule = (
    shape => 'diamond',
    label => '',
);
my %GRAPHVIZ_GRAPH_ARGS = (global => {directed => 1, combine_node_and_port => 0});
my %TypeTarget = (type => 'target'); # these are so all point at same data
my %TypeRule = (type => 'rule');

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
    my $self = {
        GraphViz => $g,
        Make => $make,
        Prefix => ($prefix||""),
        %args,
    };
    bless $self, $pkg;
}

sub GraphViz { shift->{GraphViz} ||= GraphViz2->new(global => {combine_node_and_port => 0, directed => 1}) }
sub Make     { shift->{Make} }

sub generate {
    my ($self) = @_;
    $self->GraphViz->from_graph(graphvizify($self->generate_graph));
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

my %CHR2ENCODE = ("\\" => '\\\\');
my $CHR_PAT = join '|', map quotemeta, sort keys %CHR2ENCODE;
sub _recipe2label {
    my ($recipe) = @_;
    [
        [ map {
            my $t = $_; $t =~ s/($CHR_PAT)/$CHR2ENCODE{$1}/g; "$t\\l";
        } @$recipe ]
    ];
}

sub graphvizify {
    my ($g) = @_;
    for my $v ($g->vertices) {
        my $attrs = $g->get_vertex_attributes($v);
        my $type = $attrs->{type};
        if ($type eq 'target') {
            $g->set_vertex_attributes($v, { %$attrs, graphviz => {
                label => graphviz_escape($v),
                %NodeStyleTarget,
            } });
        } elsif ($type eq 'recipe') {
            $g->set_vertex_attributes($v, { %$attrs, graphviz => {
                label => _recipe2label($attrs->{recipe}),
                %NodeStyleRecipe,
            } });
            for my $e ($g->edges_from($v)) {
                my $fromline = $g->get_edge_attribute(@$e, 'fromline');
                $g->set_edge_attributes(@$e, { graphviz => {
                    tailport => ['port' . ($fromline+1), 'e'],
                } }) if defined $fromline;
            }
        } else {
            # bare rule
            $g->set_vertex_attributes($v, { %$attrs, graphviz => \%NodeStyleRule });
        }
    }
    $g->set_graph_attribute(graphviz => \%GRAPHVIZ_GRAPH_ARGS);
    $g;
}

sub _graph_ingest {
    my ($g, $g2) = @_;
    for my $v ($g2->vertices) {
        $g->set_vertex_attributes($v, $g2->get_vertex_attributes($v));
        $g->set_edge_attributes(@$_, $g2->get_edge_attributes(@$_))
            for $g2->edges_from($v);
    }
}

sub generate_graph {
    my ($self) = @_;
    my $prefix = $self->{Prefix};
    my $g = Graph->new;
    my $m = $self->{Make};
    for my $target (sort $m->targets) {
        $g->set_vertex_attributes($prefix.$target, \%TypeTarget);
        my $make_target = $m->target($target);
        my @rules = @{ $make_target->rules };
        if (!@rules) {
            warn "No depends for target $target\n" if $V;
            next;
        }
        for my $rule (@rules) {
            my $rule_id;
            my $recipe = $rule->recipe;
            if (@$recipe) {
                $rule_id = _gen_id($recipe);
                $g->set_vertex_attributes($rule_id, { type => 'recipe', recipe => $recipe });
                my $line = 0;
                for my $cmd ($rule->exp_recipe($make_target)) {
                    my ($g2, @targets) = _find_recursive_makes($m, $cmd);
                    next if !@targets;
                    _graph_ingest($g, $g2);
                    $g->set_edge_attribute($rule_id, $_, fromline => $line)
                        for @targets;
                    $line++;
                }
            } else {
                $rule_id = _gen_id($rule);
                $g->set_vertex_attributes($rule_id, \%TypeRule);
            }
            $g->add_edge($prefix.$target, $rule_id);
            for my $dep (@{ $rule->prereqs }) {
                $g->set_vertex_attributes($prefix.$dep, \%TypeTarget);
                $g->add_edge($rule_id, $prefix.$dep);
            }
        }
    }
    $g;
}

sub _find_recmake_cd {
    my ($cmd) = @_;
    return unless $cmd =~ /\bcd\s+([^\s;&]+)\s*(?:;|&&)\s*make\s*(.*)/;
    my ($dir, $makeargs) = ($1, $2);
    require Getopt::Long;
    require Text::ParseWords;
    local @ARGV = Text::ParseWords::shellwords($makeargs);
    Getopt::Long::GetOptions("f=s" => \my $makefile);
    my ($vars, $targets) = Make::parse_args(@ARGV);
    ($dir, $makefile, $vars, $targets);
}

sub _find_recursive_makes {
    my ($make, $cmd) = @_;
    my @rec_vars;
    for my $rf (@RECMAKE_FINDS) {
        last if @rec_vars = $rf->($cmd);
    }
    unless (@rec_vars) {
        warn "can't match external make command in $cmd\n" if $V;
        return;
    }
    my ($dir, $makefile, $vars, $targets) = @rec_vars;
    my $make2 = 'Make'->new( # quoted to not call function in this module
        FunctionPackages => $make->function_packages,
        FSFunctionMap => $make->fsmap,
        InDir => $dir,
    );
    $make2->parse($makefile);
    $make2->set_var(@$_) for @$vars;
    $targets = [ $make2->{Vars}{'.DEFAULT_GOAL'} ] unless @$targets;
    my $gm2 = GraphViz::Makefile->new(undef, $make2, "$dir/"); # XXX save_pwd verwenden; -f option auswerten
    ($gm2->generate_graph, map "$dir/$_", @$targets);
}

my %GRAPHVIZ_ESCAPE = (
  "\n" => "n",
  map +($_ => $_), qw({ } " \\ < > [ ]),
);
my $GRAPHVIZ_ESCAPE_CHARS = join '|',
    map quotemeta, sort keys %GRAPHVIZ_ESCAPE;
sub graphviz_escape {
    my ($text) = @_;
    $text =~ s/($GRAPHVIZ_ESCAPE_CHARS)/\\$GRAPHVIZ_ESCAPE{$1}/gs;
    $text;
}

1;


__END__

=head1 NAME

GraphViz::Makefile - Create Makefile graphs using GraphViz

=head1 SYNOPSIS

Output to a .png file:

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    my $g = GraphViz2->new(global => {combine_node_and_port => 0, directed => 1});
    $g->from_graph(GraphViz::Makefile::graphvizify($gm->generate_graph));
    $g->run(format => "png", output_file => "makefile.png");

To output to a .ps file, just replace C<png> with C<ps> in the filename
and method above.

Or, using the deprecated mutation style:

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    $gm->generate;
    $gm->GraphViz->run(format => "png", output_file => "makefile.png");

=head1 DESCRIPTION

B<GraphViz::Makefile> uses the L<GraphViz2> and L<Make> modules to
visualize Makefile dependencies.

=head2 METHODS

=over

=item new($graphviz, $makefile, $prefix, %args)

Create a C<GraphViz::Makefile> object. The first argument should be a
C<GraphViz2> object or C<undef>. The second argument should be a
C<Make> object, the filename of a Makefile, or C<undef>. In the latter
case, the default Makefile is used. The third argument C<$prefix> is
optional and can be used to prepend a prefix to all rule names in the
graph output.

The created nodes are named C<$prefix$name>.

Further arguments (specified as key-value pairs): none at present.

=item generate

Generate the graph. Mutates the internal C<GraphViz2> object.

=item generate_graph

    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    my $graph = $gm->generate_graph;
    $gv->from_graph(GraphViz::Makefile::graphvizify($graph));
    $gv->run(format => "png", output_file => "makefile.png");

Return a L<Graph> object representing this Makefile.

=item GraphViz

Return a reference to the C<GraphViz2> object. This object will be used
for the output methods. Will only be created if used. It is recommended
to instead use the C<generate_graph> method and make the calls on an
externally-controlled L<GraphViz2> object.

=item Make

Return a reference to the C<Make> object.
 
=back

=head1 FUNCTIONS

=head2 graphviz_escape

Turn characters in the given string, that are considered special by
GraphViz, into escaped versions so that they will appear literally as
given in the visualisation.

=head2 graphvizify

    GraphViz::Makefile::graphvizify($graph);

Adds attributes to the given L<Graph> object of a makefile, to make it
be visualised well using L<GraphViz2/from_graph>.

=head1 ALTERNATIVES

There's another module doing the same thing: L<Makefile::GraphViz>.

=head1 AUTHOR

Slaven Rezic <srezic@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2002,2003,2005,2008,2013 Slaven Rezic. All rights reserved.
This module is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<GraphViz2>, L<Make>, L<make(1)>, L<tkgvizmakefile>.

=cut
