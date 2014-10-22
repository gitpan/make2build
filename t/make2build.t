#! /usr/local/bin/perl

use strict;
use vars qw($SCRIPT);
use warnings;

use Test::More tests => 1;

$SCRIPT = '../make2build.pl';

ok( (-r $SCRIPT && -w $SCRIPT && -x $SCRIPT), "(-rwx) $SCRIPT" );
