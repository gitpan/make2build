#! /usr/local/bin/perl

$VERSION = '0.02';

use strict;
#use warnings; 
#no warnings 'redefine';
use Data::Dumper;
use ExtUtils::MakeMaker;

our(
    %convert,
    %sorted_order,
    %default_args,
    $header,
    $footer,
    $INTEND,
);


my $MAKEFILE_PL    = 'Makefile.PL';
my $BUILD_PL       = 'Build.PL';

my $DEBUG          = 0;
my $LEN_INTEND     = 3;

# Data::Dumper
my $DD_INDENT      = 2;
my $DD_SORTKEYS    = 1;


*ExtUtils::MakeMaker::WriteMakefile = \&_convert;

_run_makefile();

sub _run_makefile {
    -e $MAKEFILE_PL
      ? do $MAKEFILE_PL
      : die "No $MAKEFILE_PL found\n";
}

sub _convert {
    local(
          %convert, 
          %sorted_order, 
	  %default_args,
	  $header,
	  $footer,
    );
    
    _get_data();

    print "Converting $MAKEFILE_PL -> $BUILD_PL\n";
    
    _write(_dump(&_args_build));
}

sub _get_data {
    local $/ = '1;';
    local $_ = <DATA>;
    
    my $regexp = qr/#\s+.*\s+?-\s+?\n/;    #  # description
    my @data = split /$regexp/;            #  -
    
    shift @data;                           # Superfluos items			
    chomp $data[-1]; $/ = "\n";            
    chomp $data[-1];
    
    %convert         = split /\s+/, shift @data;
    %sorted_order    = split /\s+/, shift @data;
    %default_args    = split /\s+/, shift @data;
    $header          = shift @data;
    $footer          = shift @data;
}

sub _args_build { 
    my %args_make = @_;
    my @args_build = (\%default_args); 
    
    for my $arg (keys %args_make) {
        next unless $convert{$arg};
	
        if (ref $args_make{$arg} eq 'HASH') {                             ### HASH CONVERSION
 	    my(%subargs, $count_subargs);  
	    my($total_subargs) = scalar %{$args_make{$arg}} =~ /^(.)/;    
	    
	    for my $subarg (keys %{$args_make{$arg}}) {
	        $subargs{$subarg} = $args_make{$arg}{$subarg};
	    }
	    
            my %tmphash;
	    %{$tmphash{$convert{$arg}}} = %subargs;
	    push @args_build, \%tmphash;
	}
	elsif (ref $args_make{$arg} eq 'ARRAY') {                         ### ARRAY CONVERSION
	    warn "Warning: $arg - array conversion not supported\n";
	}
	#
	# One-dimensional hash values (scalars),
	# don't justify as SCALARS.
	#
        elsif (ref $args_make{$arg} eq '') { 	                          ### SCALAR CONVERSION
	    my %tmphash;
	    $tmphash{$convert{$arg}} = $args_make{$arg};
	    push @args_build, \%tmphash;
	}
	else { 
	    warn "Warning: $arg - unknown type of argument";
	}
    }    
    
    @args_build = @{_sort(\@args_build)}    if %sorted_order;
    
    return \@args_build;
}

sub _sort {
    my($args) = @_;
    
    my $sorted;
    do {
        for (my $i = 0; $i < @$args; $i++) {
	    $sorted = 1;    
            my($arg) = keys %{$args->[$i]};
	    
            if ($i != $sorted_order{$arg}) {
                $sorted = 0;
	        my $insert = splice(@$args, $i, 1);
	        push @$args, $insert;
	    }
        }
    } 
    until ($sorted);
    
    return $args;    
}

sub _dump {
    my($args) = @_;

    $Data::Dumper::Indent       = $DD_INDENT || 2;
    $Data::Dumper::Quotekeys    = 0;
    $Data::Dumper::Sortkeys     = $DD_SORTKEYS;
    $Data::Dumper::Terse        = 1;
    
    my $d = Data::Dumper->new([ @$args ]);
    
    return [ $d->Dump ];
}

sub _write { 
    local $INTEND = ' ' x $LEN_INTEND;
    
    local *F_BUILD; 

    _open_build_pl();

    _write_header();
    &_write_args;
    _write_footer();
    
    _close_build_pl();
}

sub _open_build_pl {
    open F_BUILD, ">$BUILD_PL" or 
      die "Couldn't open $BUILD_PL: $!";
      
    select F_BUILD;
}

sub _write_header {
    local $INTEND = $INTEND;
    chop($INTEND);
    
    $header =~ s{\$INTEND}{$INTEND}g;
    
    _debug("\n$BUILD_PL written:\n");
    _debug($header);
    
    print $header;
}

sub _write_args {
    my($args) = @_;
    
    for my $arg (@$args) {                                        
        if ($arg =~ m#=> \{#o) {                                     ### HASH OUTPUT
	    $arg =~ s#^ \{ .*?\n (.*? \}) \s+ \} $#$1#osx;           # Remove redundant parentheses
	    
	    my @arg;        
            while ($arg =~ s#^ (.*?\n) (.*) $#$2#osx) {              # One element per each line
                push @arg, $1;
            };
	    
	    my($whitespace) = $arg[0] =~ m#^ (\s+) (?: \w+)#ox;      # Gather whitespace up to hash key in order 
	    my $shorten = length($whitespace);                       # to recreate native Dump() intendation.
	    
            for my $arg (@arg) {
	        chomp($arg);
		
	        $arg =~ s#^ \s{$shorten} (.*) $#$1#ox;               # Remove additional whitespace
		$arg =~ s#(\S+) => (\w+)#'$1' => $2#o;               # Add quotes to hash keys within multiple hashes
		$arg =~ s# '(\d+)' (?: , | ) $#$1#ox;                # Remove quotes on version numbers
	        $arg .= ','    if ($arg =~ m#(?: \d+ | \}) $#ox);    # Add comma where appropriate (version numbers, parentheses)
		
		_debug("$INTEND$arg\n");
		
		print "$INTEND$arg\n";
            }
	}
	else {                                                       ### SCALAR OUTPUT
	    chomp($arg);
	
            $arg =~ s#^ \{ \s+ (.*) \s+ \} $#$1#ox;                  # Remove redundant parentheses
	    
	    _debug("$INTEND$arg,\n");
	    
	    print "$INTEND$arg,\n";
	}
    }
}

sub _write_footer {
    local $INTEND = $INTEND;
    chop($INTEND);
    
    $footer =~ s{\$INTEND}{$INTEND}g;
    
    _debug($footer);
    
    print $footer;
}

sub _close_build_pl {
    close F_BUILD or
      die "Couldn't close $BUILD_PL: $!";
      
    select STDOUT; 
}

sub _debug { 
    print STDOUT @_    if $DEBUG; 
}

__DATA__
 
# args conversion 
- 
NAME         module_name
PREREQ_PM    requires
 
# sort order 
- 
module_name  0
license      1
requires     2
 
# default args 
- 
license    perl
 
# header 
- 

use Module::Build;

my $b = Module::Build->new
$INTEND(
# footer 
- 
$INTEND create_makefile_pl => 'traditional',
$INTEND);
  
$b->create_build_script;

1;
