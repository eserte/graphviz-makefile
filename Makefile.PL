# -*- perl -*-
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile
  (
    'NAME'	=> 'Graphviz::Makefile',
    'VERSION_FROM' => 'Makefile.pm', # finds $VERSION
    'PREREQ_PM'    => {'Graphviz' => 0, 'Make' => 0},
);

sub MY::postamble {
    if (defined $ENV{USER} && $ENV{USER} eq 'eserte') {
	<<'EOF';
release :: dist
	cpan-upload $(DISTVNAME).tar$(SUFFIX)

EOF
    }
}
