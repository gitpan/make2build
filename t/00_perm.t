#! /usr/local/bin/perl

use strict;
use vars qw($SCRIPT);
use warnings;

use Test::More tests => 1;

$SCRIPT = '../script/make2build.PL';

is( (-e $SCRIPT && -r $SCRIPT && -w $SCRIPT && -x $SCRIPT), 
  1, "(-e -rwx) $SCRIPT" ); 
