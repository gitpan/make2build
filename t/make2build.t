#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 1;

my $SCRIPT = 'make2build.pl';

ok((-r $SCRIPT && -x $SCRIPT), "(-rx) $SCRIPT");