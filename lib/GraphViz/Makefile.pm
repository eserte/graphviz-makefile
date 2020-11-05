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

our $VERSION = '1.18';

our $V = 0 unless defined $V;
my @ALLOWED_ARGS = qw();
my %ALLOWED_ARGS = map {($_,undef)} @ALLOWED_ARGS;

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

sub GraphViz { shift->{GraphViz} ||= GraphViz2->new(global => {combine_node_and_port => 0}) }
sub Make     { shift->{Make}     }

sub generate {
    my ($self, $target) = @_;
    $target = "all" if !defined $target;
    my ($nodes, $edges) = $self->generate_tree($self->{Make}->expand($target));
    my $g = $self->GraphViz;
    $g->add_node(
        name => $_,
        label => graphviz_escape($_),
        %{ $nodes->{$_} },
    ) for sort keys %$nodes;
    for my $edge_start (sort keys %$edges) {
        my $sub_edges = $edges->{$edge_start};
        $g->add_edge(
            from => $edge_start,
            to => $_,
            %{ $sub_edges->{$_} },
        ) for keys %$sub_edges;
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

sub _add_edge {
    my ($edges, $from, $to) = @_;
    my @edge = ($from, $to);
    $edges->{$edge[0]}{$edge[1]} ||= {};
    warn "$edge[0] => $edge[1]\n" if $V >= 2;
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

# mutates $nodes and $edges and $to_visit
sub _node2deps {
    my ($prefix, $target, $deps, $nodes, $edges, $to_visit) = @_;
    for my $dep (@$deps) {
        $nodes->{$prefix.$dep} ||= \%NodeStyleTarget;
        _add_edge($edges, $target, $prefix.$dep);
        $to_visit->{$dep}++;
    }
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
    if (!@{ $make_target->rules }) {
        warn "No depends for target $target\n" if $V;
        return;
    }
    my ($recipe_rules, $bare_rules) = _rules_partition($make_target);
    my @merged_rules = _rules_merge($recipe_rules, $bare_rules);
    my %to_visit;
    if (@merged_rules) {
        for my $recipe_rule (@merged_rules) {
            my $recipe_id = _gen_id($recipe_rule->{recipe});
            my $recipe_label = _recipe2label($recipe_rule->{recipe});
            $nodes->{$recipe_id} ||= { %NodeStyleRecipe, label => $recipe_label };
            _add_edge($edges, $prefix.$target, $recipe_id);
            _node2deps(
                $prefix, $recipe_id, $recipe_rule->{prereqs}, $nodes, $edges, \%to_visit,
            );
        }
    } else {
        _node2deps(
            $prefix, $prefix.$target, $_->prereqs, $nodes, $edges, \%to_visit,
        ) for @$bare_rules;
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
        $self->GraphViz->add_edge(
            from => $target_name,
            to => "$dir/$rule",
        );
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

my %GRAPHVIZ_ESCAPE = (
  "\n" => "n",
  map +($_ => $_), qw({ } " \\ < > [ ]),
);
my $GRAPHVIZ_ESCAPE_CHARS = join '|',
    map quotemeta, sort keys %GRAPHVIZ_ESCAPE;
my %GRAPHVIZ_UNESCAPE = (
  reverse(%GRAPHVIZ_ESCAPE),
  l => "\n", "\n" => "",
  ' ' => ' ',
);
my %GRAPHVIZ_RECORD_UNESCAPE = (
  '{' => [ '^\{' ],
  '}' => [ '\}$' ],
  '\\l}' => [ '\\\\l\}' ],
  '\\l|' => [ '\\\\l\|', "\n" ],
  '|' => [ '\|', "\n" ],
  '' => [ '<[^>]+>\s*' ],
);
my $GRAPHVIZ_RECORD_UNESCAPE_CHARS = join '|',
    map $GRAPHVIZ_RECORD_UNESCAPE{$_}[0], sort keys %GRAPHVIZ_RECORD_UNESCAPE;
sub graphviz_escape {
    my ($text) = @_;
    $text =~ s/($GRAPHVIZ_ESCAPE_CHARS)/\\$GRAPHVIZ_ESCAPE{$1}/gs;
    $text;
}
sub graphviz_unescape {
    my ($text, $shape) = @_;
    my $record_pat = $shape eq 'record' ? $GRAPHVIZ_RECORD_UNESCAPE_CHARS : '';
    $text =~ s/($record_pat)|\\(.)/
        $2 ? do {
            my $e = $GRAPHVIZ_UNESCAPE{$2};
            die "Unknown GraphViz escape '$2' in '$text'" unless defined $e;
            $e;
        } : $1 ? $GRAPHVIZ_RECORD_UNESCAPE{$1}[1] || '' : ''
    /gse;
    $text;
}

sub graphviz2tk {
    my($text) = @_;
    require Text::ParseWords;
    my $tfm = sub { my($x,$y) = @_; ($x*100,$y*100) };
    my @methods;
    foreach my $l (split /(?<!\\)\n/, $text) {
        # spec from https://www.graphviz.org/doc/info/output.html#d:plain
        my(@w) = Text::ParseWords::quotewords('\s+', 1, $l);
        my $type = shift @w;
        if ($type eq 'graph') {
            push @methods, [ 'configure', -scrollregion => [$tfm->(0,0),$tfm->($w[1],$w[2])] ];
        } elsif ($type eq 'node') {
            my ($name, $x, $y, $width, $height, $label, $style, $shape, $color, $fillcolor) = @w;
            ($x,$y) = $tfm->($x, $y);
            ($width,$height) = $tfm->($width, $height);
            my $method = 'create' . ($shape =~ /^(box|record)$/ ? 'Rectangle' : 'Oval');
            push @methods, [ $method, $x-$width/2,$y-$height/2,$x+$width/2,$y+$height/2, -fill=>$fillcolor ];
            $label =~ s/\A"(.*)"\z/$1/gs;
            $label = graphviz_unescape($label, $shape);
            chomp $label;
            push @methods, [ 'createText', $x,$y,-text => $label, -tag => ["rule","rule_$label"] ];
        } elsif ($type eq 'edge') {
            my ($from, $to, $no) = splice @w, 0, 3;
            my @coords;
            push @coords, $tfm->(splice @w, 0, 2) while $no-- > 0;
            push @methods, [ 'createLine', @coords, -arrow => "last", -smooth => 1 ];
        } elsif ($type eq 'stop') {
            last;
        } else {
            warn "Ignore directive $type @w\n";
        }
    }
    @methods;
}

1;


__END__

=head1 NAME

GraphViz::Makefile - Create Makefile graphs using GraphViz

=head1 SYNOPSIS

Output to a .png file:

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    my $g = GraphViz2->new(global => {combine_node_and_port => 0});
    my ($nodes, $edges) = $gm->generate_tree("all"); # or another makefile target
    $g->add_node(
        name => $_,
        label => GraphViz::Makefile::graphviz_escape($_),
        %{ $nodes->{$_} },
    ) for sort keys %$nodes;
    for my $edge_start (sort keys %$edges) {
        my $sub_edges = $edges->{$edge_start};
        $g->add_edge(
            from => $edge_start,
            to => $_,
            %{ $sub_edges->{$_} },
        ) for keys %$sub_edges;
    }
    $g->run(format => "png", output_file => "makefile.png");

To output to a .ps file, just replace C<png> with C<ps> in the filename
and method above.

Or, using the deprecated mutation style:

    use GraphViz::Makefile;
    my $gm = GraphViz::Makefile->new(undef, "Makefile");
    $gm->generate("all"); # or another makefile target
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

The created nodes are named C<rule_$prefix$name>.

Further arguments (specified as key-value pairs): none at present.

=item generate($rule)

Generate the graph, beginning at the named Makefile rule. If C<$rule>
is not given, C<all> is used instead. Mutates the internal C<GraphViz2>
object.

=item find_recursive_makes($target_name, $cmd)

Search the command for a recursive make (change directory, call
make). Incorporates into this graph with the subdirectory's target as
C<dirname/targetname>.

=item generate_tree($target)

    my ($nodes, $edges) = $gm->generate_tree("all"); # or another makefile target
    $g->add_node(
        name => $_,
        label => GraphViz::Makefile::graphviz_escape($_),
        %{ $nodes->{$_} },
    ) for sort keys %$nodes;
    for my $edge_start (sort keys %$edges) {
        my $sub_edges = $edges->{$edge_start};
        $g->add_edge(
            from => $edge_start,
            to => $_,
            %{ $sub_edges->{$_} },
        ) for keys %$sub_edges;
    }

Return a hash-refs of nodes and edges. The values (or second-level
values for edges) are hash-refs of further arguments for the GraphViz2
C<add_node> and C<add_edge> methods respectively.

=item GraphViz

Return a reference to the C<GraphViz2> object. This object will be used
for the output methods. Will only be created if used. It is recommended
to instead use the C<generate_tree> method and make the calls on an
externally-controlled L<GraphViz2> object.

=item Make

Return a reference to the C<Make> object.
 
=back

=head1 FUNCTIONS

=head2 graphviz2tk

    my $c = $w->Subwidget("Graph");
    for my $m (GraphViz::Makefile::graphviz2tk($graphviz2->run(format=>"plain")->dot_output)) {
        my ($method, @args) = @$m;
        $c->$method(@args);
    }

Given the result of C<< $graphviz2->run(format=>"plain")->dot_output >>,
returns list of array-refs whose first element is a Tk Graph method call,
and the rest is the arguments.

=head2 graphviz_escape

=head2 graphviz_unescape

These turn characters considered special by GraphViz into escaped versions,
and back.

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
