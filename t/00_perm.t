#! /usr/local/bin/perl

use strict;
use warnings;

use Test::More tests => 1;

my $SCRIPT = '../script/make2build.PL';

is( (-e $SCRIPT && -r $SCRIPT && -w $SCRIPT && -x $SCRIPT), 
  1, "(-e -rwx) $SCRIPT" ); 
