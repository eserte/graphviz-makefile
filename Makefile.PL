# -*- perl -*-
use ExtUtils::MakeMaker;

$is_devel_host = defined $ENV{USER} && $ENV{USER} eq 'eserte' && ($^O =~ /bsd/i || $ENV{PERL_RELEASE_READY}) && -f "../../perl.release.mk";
$eumm_recent_enough = $ExtUtils::MakeMaker::VERSION >= 6.54;

if (!$eumm_recent_enough) {
    *MY::dist_core = sub {
	<<'EOF';
dist :
	$(NOECHO) $(ECHO) "Sorry, use a newer EUMM!"

EOF
    };
}

WriteMakefile(
    NAME		=> 'GraphViz::Makefile',
    VERSION_FROM	=> 'lib/GraphViz/Makefile.pm',
    EXE_FILES		=> [ glob 'scripts/*' ],
    PREREQ_PM		=> {'GraphViz2' => '2.58', 'Make' => '2.003'},
    TEST_REQUIRES => {
        'Test::More' => '1.001002',
        'Test::Snapshot' => '0.06',
    },
    LICENSE	      => 'perl',
    MIN_PERL_VERSION => '5.010', # GraphViz2
    ABSTRACT_FROM  => 'lib/GraphViz/Makefile.pm', # retrieve abstract from module
    AUTHOR         => 'Slaven Rezic <srezic@cpan.org>',
    ($eumm_recent_enough ?
      (META_ADD => { resources => { repository => 'git://github.com/eserte/graphviz-makefile.git' } }) : ()),
);

sub MY::postamble {
    my $postamble = '';

    if ($is_devel_host) {
	$postamble .= <<'EOF';

PERL_TEST_DISTRIBUTION_OPTS=not podcover

.include "../../perl.release.mk"
.include "../../perl.git.mk"

EOF
    }

    $postamble;
}
