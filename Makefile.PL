use ExtUtils::MakeMaker;
WriteMakefile(
    NAME         => 'make2build',
    VERSION_FROM => 'script/make2build.PL',
    PL_FILES     => { 'script/make2build.PL' => 'script/make2build' },
    PREREQ_PM    => { Data::Dumper        => 0,
                      ExtUtils::MakeMaker => 0, },
    ($] >= 5.005 
      ? (ABSTRACT_FROM => 'script/make2build.PL') : ()
    ),
);
