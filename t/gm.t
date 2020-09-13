#!/usr/bin/perl -w
# -*- perl -*-

# Author: Slaven Rezic

use strict;
use FindBin;

use GraphViz::Makefile;

BEGIN {
    if (!eval q{
        use Test::More;
        use File::Temp;
        1;
    }) {
        print "1..0 # skip: no Test::More and/or File::Temp modules\n";
        exit;
    }
}

my $node_target = \%GraphViz::Makefile::NodeStyleTarget;
my $node_recipe = \%GraphViz::Makefile::NodeStyleRecipe;
my $model_expected = [
  {
    model => $node_target,
    'data/features.tab' => $node_target,
    otherfile => $node_target,
    ':recipe:1' => { %$node_recipe, label => 'perl prog1.pl $<\\l' },
    ':recipe:2' => { %$node_recipe, label => 'perl prog3.pl $< > $@\\l' },
  },
  {
    model => { ':recipe:1' => {} },
    'data/features.tab' => { ':recipe:2' => {} },
    ':recipe:1' => { 'data/features.tab' => {} },
    ':recipe:2' => { 'otherfile' => {} },
  },
];
my $modelrev_expected = [
  $model_expected->[0],
  {
    ':recipe:1' => { model => {} },
    ':recipe:2' => { 'data/features.tab' => {} },
    'data/features.tab' => { ':recipe:1' => {} },
    'otherfile' => { ':recipe:2' => {} },
  },
];
my $modelprefix_expected = [
  {
    testmodel => $node_target,
    'testdata/features.tab' => $node_target,
    testotherfile => $node_target,
    ':recipe:1' => { %$node_recipe, label => 'perl prog1.pl $<\\l' },
    ':recipe:2' => { %$node_recipe, label => 'perl prog3.pl $< > $@\\l' },
  },
  {
    testmodel => { ':recipe:1' => {} },
    'testdata/features.tab' => { ':recipe:2' => {} },
    ':recipe:1' => { 'testdata/features.tab' => {} },
    ':recipe:2' => { 'testotherfile' => {} },
  },
];
my $mgv_expected = [
  {
    all => $node_target,
    foo => $node_target,
    bar => $node_target,
    blah => $node_target,
    boo => $node_target,
    howdy => $node_target,
    buz => $node_target,
    ':recipe:1' => { %$node_recipe, label => 'echo hallo perl\\\\lib double\\\\\\\\l\\l' },
    ':recipe:2' => { %$node_recipe, label => 'echo Hi\\l' },
    ':recipe:3' => { %$node_recipe, label => 'echo Hey\\l' },
  },
  {
    all => { ':recipe:1' => {} },
    ':recipe:1' => { 'bar' => {}, 'foo' => {} },
    foo => { ':recipe:2' => {}, ':recipe:3' => {} },
    ':recipe:2' => { 'blah' => {}, 'boo' => {} },
    ':recipe:3' => { 'buz' => {}, 'howdy' => {} },
  },
];
my $mgvnorecipe_expected = [
  {
    all => $node_target,
    foo => $node_target,
    bar => $node_target,
    blah => $node_target,
    boo => $node_target,
    howdy => $node_target,
    buz => $node_target,
    ':recipe:1' => { %$node_recipe, label => 'echo Hi\\l' },
    ':recipe:2' => { %$node_recipe, label => 'echo Hey\\l' },
  },
  {
    all => { 'bar' => {}, 'foo' => {} },
    foo => { ':recipe:1' => {}, ':recipe:2' => {} },
    ':recipe:1' => { 'blah' => {}, 'boo' => {} },
    ':recipe:2' => { 'buz' => {}, 'howdy' => {} },
  },
];
my $make_subst = <<'EOF';
DATA=data

model: $(DATA)/features.tab
	perl prog1.pl $<

$(DATA)/features.tab: otherfile
	perl prog3.pl $< > $@
EOF
my @makefile_tests = (
    ["$FindBin::RealBin/../Makefile", "all", '', {}, undef],
    [\<<'EOF', "model", '', {}, $model_expected],
model: data/features.tab
	perl prog1.pl $<

data/features.tab: otherfile
	perl prog3.pl $< > $@
EOF
    [\$make_subst, "model", '', {}, $model_expected],
    [\$make_subst, "model", '', { reversed => 1 }, $modelrev_expected],
    [\$make_subst, "model", 'test', {}, $modelprefix_expected],
    [\<<'EOF', "all", '', {}, $mgv_expected],
all: foo
all: bar
	echo hallo perl\lib double\\l

any: foo hiya
	echo larry
	echo howdy
any: blah blow

foo:: blah boo
	echo Hi
foo:: howdy buz
	echo Hey
EOF
    [\<<'EOF', "all", '', {}, $mgvnorecipe_expected],
all: foo
all: bar

any: foo hiya
	echo larry
	echo howdy
any: blah blow

foo:: blah boo
	echo Hi
foo:: howdy buz
	echo Hey
EOF
);
plan tests => 1 + @makefile_tests * 4;

SKIP: {
    skip("tkgvizmakefile test only with INTERACTIVE=1 mode", 1) if !$ENV{INTERACTIVE};
    system("$^X", "-Mblib", "blib/script/tkgvizmakefile", "-reversed", "-prefix", "test-");
    is $?, 0, "Run tkgvizmakefile";
}

for my $def (@makefile_tests) {
    my ($makefile, $target, $prefix, $extra, $expected) = @$def;
    GraphViz::Makefile::_reset_id();
    my $gm = GraphViz::Makefile->new(undef, $makefile, $prefix, %$extra);
    isa_ok($gm, "GraphViz::Makefile");
    if (defined $expected) {
        my $got = [ $gm->generate_tree($target) ];
        is_deeply $got, $expected, 'generate_tree' or diag explain $got;
    }
    $gm->generate($target);

    my $png = eval { $gm->GraphViz->as_png };
    SKIP: {
        skip("Cannot create png file: $@", 2)
            if !$png;

        my ($fh, $filename) = File::Temp::tempfile(SUFFIX => ".png",
                                              UNLINK => 1);
        print $fh $gm->GraphViz->as_png;
        close $fh;

        ok(-s $filename, "Non-empty png file for makefile $makefile");

        skip("Display png file only with INTERACTIVE=1 mode", 1) if !$ENV{INTERACTIVE};
        skip("ImageMagick/display not available", 1) if !is_in_path("display");

        system("display", $filename);
        pass("Displayed...");
    }
}

SKIP: {
  skip "graphviz2tk test only with INTERACTIVE=1 mode", 1 if !$ENV{INTERACTIVE};
  no warnings 'qw';
  GraphViz::Makefile::_reset_id();
  my $gm = GraphViz::Makefile->new(undef, $makefile_tests[5][0]);
  $gm->generate;
  my $got_tk = [ GraphViz::Makefile::graphviz2tk($gm->GraphViz->as_plain) ];
  is_deeply $got_tk, [
    [ qw(configure -scrollregion), [ 0, 0, '375', '450' ] ],
    [ qw(createRectangle 35.415 300 239.585 350 -fill #dddddd) ],
    [ qw(createText 137.5 325 -text), 'echo hallo perl\\lib double\\\\l', -tag => [ 'rule', 'rule_echo hallo perl\\lib double\\\\l' ] ],
    [ qw(createRectangle 100 100 175 150 -fill #dddddd) ],
    [ qw(createText 137.5 125 -text), 'echo Hi', -tag => [ 'rule', 'rule_echo Hi' ] ],
    [ qw(createRectangle 200 100 275 150 -fill #dddddd) ],
    [ qw(createText 237.5 125 -text), 'echo Hey', -tag => [ 'rule', 'rule_echo Hey' ] ],
    [ qw(createRectangle 100 400 175 450 -fill #ffff99) ],
    [ qw(createText 137.5 425 -text), 'all', -tag => [ 'rule', 'rule_all' ] ],
    [ qw(createRectangle 50 200 125 250 -fill #ffff99) ],
    [ qw(createText 87.5 225 -text), 'bar', -tag => [ 'rule', 'rule_bar' ] ],
    [ qw(createRectangle 0 0 75 50 -fill #ffff99) ],
    [ qw(createText 37.5 25 -text), 'blah', -tag => [ 'rule', 'rule_blah' ] ],
    [ qw(createRectangle 100 0 175 50 -fill #ffff99) ],
    [ qw(createText 137.5 25 -text), 'boo', -tag => [ 'rule', 'rule_boo' ] ],
    [ qw(createRectangle 200 0 275 50 -fill #ffff99) ],
    [ qw(createText 237.5 25 -text), 'buz', -tag => [ 'rule', 'rule_buz' ] ],
    [ qw(createRectangle 150 200 225 250 -fill #ffff99) ],
    [ qw(createText 187.5 225 -text), 'foo', -tag => [ 'rule', 'rule_foo' ] ],
    [ qw(createRectangle 300 0 375 50 -fill #ffff99) ],
    [ qw(createText 337.5 25 -text), 'howdy', -tag => [ 'rule', 'rule_howdy' ] ],
    [ qw(createLine 125.14 299.58 119.45 288.51 112.57 275.14 106.26 262.87 -arrow last -smooth 1) ],
    [ qw(createLine 149.86 299.58 155.55 288.51 162.43 275.14 168.74 262.87 -arrow last -smooth 1) ],
    [ qw(createLine 112.78 99.579 100.55 87.688 85.58 73.134 72.221 60.145 -arrow last -smooth 1) ],
    [ qw(createLine 137.5 99.579 137.5 88.865 137.5 75.99 137.5 64.045 -arrow last -smooth 1) ],
    [ qw(createLine 237.5 99.579 237.5 88.865 237.5 75.99 237.5 64.045 -arrow last -smooth 1) ],
    [ qw(createLine 262.22 99.579 274.45 87.688 289.42 73.134 302.78 60.145 -arrow last -smooth 1) ],
    [ qw(createLine 137.5 399.58 137.5 388.86 137.5 375.99 137.5 364.05 -arrow last -smooth 1) ],
    [ qw(createLine 175.14 199.58 169.45 188.51 162.57 175.14 156.26 162.87 -arrow last -smooth 1) ],
    [ qw(createLine 199.86 199.58 205.55 188.51 212.43 175.14 218.74 162.87 -arrow last -smooth 1) ],
  ], 'graphviz2tk' or diag explain $got_tk;
}

######################################################################
# REPO BEGIN
# REPO NAME file_name_is_absolute /home/e/eserte/work/srezic-repository 
# REPO MD5 89d0fdf16d11771f0f6e82c7d0ebf3a8

=head2 file_name_is_absolute($file)

=for category File

Return true, if supplied file name is absolute. This is only necessary
for older perls where File::Spec is not part of the system.

=cut

BEGIN {
    if (eval { require File::Spec; defined &File::Spec::file_name_is_absolute }) {
        *file_name_is_absolute = \&File::Spec::file_name_is_absolute;
    } else {
        *file_name_is_absolute = sub {
            my $file = shift;
            my $r;
            if ($^O eq 'MSWin32') {
                $r = ($file =~ m;^([a-z]:(/|\\)|\\\\|//);i);
            } else {
                $r = ($file =~ m|^/|);
            }
            $r;
        };
    }
}
# REPO END

# REPO BEGIN
# REPO NAME is_in_path /home/e/eserte/work/srezic-repository 
# REPO MD5 81c0124cc2f424c6acc9713c27b9a484

=head2 is_in_path($prog)

=for category File

Return the pathname of $prog, if the program is in the PATH, or undef
otherwise.

DEPENDENCY: file_name_is_absolute

=cut

sub is_in_path {
    my ($prog) = @_;
    return $prog if (file_name_is_absolute($prog) and -f $prog and -x $prog);
    require Config;
    my $sep = $Config::Config{'path_sep'} || ':';
    foreach (split(/$sep/o, $ENV{PATH})) {
        if ($^O eq 'MSWin32') {
            # maybe use $ENV{PATHEXT} like maybe_command in ExtUtils/MM_Win32.pm?
            return "$_\\$prog"
                if (-x "$_\\$prog.bat" ||
                    -x "$_\\$prog.com" ||
                    -x "$_\\$prog.exe" ||
                    -x "$_\\$prog.cmd");
        } else {
            return "$_/$prog" if (-x "$_/$prog" && !-d "$_/$prog");
        }
    }
    undef;
}
# REPO END

