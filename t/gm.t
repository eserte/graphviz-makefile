# -*- perl -*-

# Author: Slaven Rezic

use strict;
use warnings;
use FindBin;

use GraphViz::Makefile;
use File::Spec::Functions qw(file_name_is_absolute);
use Test::More;
use Test::Snapshot;

my $node_target = \%GraphViz::Makefile::NodeStyleTarget;
my $node_recipe = \%GraphViz::Makefile::NodeStyleRecipe;
my $make_subst = <<'EOF';
DATA=data

model: $(DATA)/features.tab
	perl prog1.pl $<

$(DATA)/features.tab: otherfile
	perl prog3.pl $< > $@
EOF
my @makefile_tests = (
    ["$FindBin::RealBin/../Makefile", "all", '', {}, undef],
    [\<<'EOF', "model", '', {}, 'model_expected'],
model: data/features.tab
	perl prog1.pl $<

data/features.tab: otherfile
	perl prog3.pl $< > $@
EOF
    [\$make_subst, "model", '', {}, 'model_expected'],
    [\$make_subst, "model", 'test', {}, 'modelprefix_expected'],
    [\<<'EOF', "all", '', {}, 'mgv_expected'],
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
    [\<<'EOF', "all", '', {}, 'mgvnorecipe_expected'],
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

SKIP: {
    skip("tkgvizmakefile test only with INTERACTIVE=1 mode", 1) if !$ENV{INTERACTIVE};
    system("$^X", "-Mblib", "blib/script/tkgvizmakefile", "-reversed", "-prefix", "test-");
    is $?, 0, "Run tkgvizmakefile";
}

my $is_in_path_display = is_in_path("display");
for my $def (@makefile_tests) {
    my ($makefile, $target, $prefix, $extra, $expected) = @$def;
    diag "Makefile:\n" . join '', explain $makefile;
    GraphViz::Makefile::_reset_id();
    my $gm = GraphViz::Makefile->new(undef, $makefile, $prefix, %$extra);
    isa_ok($gm, "GraphViz::Makefile");
    if (defined $expected) {
        my $got = [ $gm->generate_tree($target) ];
        is_deeply_snapshot $got, $expected or diag explain $got;
    }
    $gm->generate($target);
    my $png = eval { $gm->GraphViz->run(format=>"png")->dot_output };
    SKIP: {
        skip("Cannot create png file: $@", 2)
            if !$png;
        require File::Temp;
        my ($fh, $filename) = File::Temp::tempfile(SUFFIX => ".png",
                                              UNLINK => 1);
        print $fh $png;
        close $fh;
        ok -s $filename, "Non-empty png file";
        skip("Display png file only with INTERACTIVE=1 mode", 1) if !$ENV{INTERACTIVE};
        skip("ImageMagick/display not available", 1) if !$is_in_path_display;
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
  my $got_tk = [ GraphViz::Makefile::graphviz2tk($gm->GraphViz->run(format=>"plain")->dot_output) ];
  is_deeply_snapshot $got_tk, 'graphviz2tk';
}

done_testing;

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

