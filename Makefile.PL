use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         =>  'make2build',
    VERSION_FROM =>  'make2build.pl', # finds $VERSION
    PREREQ_PM    => {},
    PL_FILES     => {},
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005 
       (ABSTRACT_FROM => 'make2build.pl',
        AUTHOR        => 'Steven Schubiger <steven@accognoscere.org>') : ()),
);
