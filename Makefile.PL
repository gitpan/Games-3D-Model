use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Games::3D::Model',
    'VERSION_FROM'	=> 'lib/Games/3D/Model.pm', # finds $VERSION
    'PREREQ_PM'		=> {
			SDL => '1.20.0',
			Games::3D::World => '0.04',
			}, # e.g., Module::Name => 1.1
    'LIBS'		=> [ ], # e.g., '-lm'
    'DEFINE'		=> '', # e.g., '-DHAVE_SOMETHING'
    'INC'		=> '', # e.g., '-I/usr/include/other'
);
