#! /usr/local/bin/perl

$VERSION = '0.01';

use strict;
#use warnings; 
#no warnings 'redefine';
use Data::Dumper;
use ExtUtils::MakeMaker;

our(%convert,
    %sorted_order,
    %default_args,
    $header,
    $footer,
    $INTEND,
);


my $MAKEFILE_PL = 'Makefile.PL';
my $BUILD_PL    = 'Build.PL';

my $DEBUG      = 0;
my $LEN_INTEND = 3;

# Data::Dumper
my $DD_INDENT    = 2;
my $DD_SORTKEYS  = 1;


*ExtUtils::MakeMaker::WriteMakefile = \&_convert;

_run_makefile();

sub _run_makefile {
    -e $MAKEFILE_PL
      ? do $MAKEFILE_PL
      : die "No $MAKEFILE_PL found\n";
}

sub _convert {
    local(%convert, 
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
    
    #  # description
    #  -
    my $regexp = qr/#\s+.*\s+?-\s+?\n/;
    my @data = split /$regexp/;
    
    # Superfluos items
    shift @data;
    chomp $data[-1]; $/ = "\n";   
    chomp $data[-1];
    
    %convert      = split /\s+/, shift @data;
    %sorted_order = split /\s+/, shift @data;
    %default_args = split /\s+/, shift @data;
    $header       = shift @data;
    $footer       = shift @data;
}

sub _args_build { 
    my %args_make = @_;
    my @args_build = (_insert_args()); 
    
    for my $arg (keys %args_make) {
        next unless $convert{$arg};
	
	# HASH CONVERSION
        if (ref $args_make{$arg} eq 'HASH') { 
 	    my(%subargs, $count_subargs);  
	    my($total_subargs) = scalar %{$args_make{$arg}} =~ /^(.)/;
	    
	    for my $subarg (keys %{$args_make{$arg}}) {
	        $subargs{$subarg} = $args_make{$arg}{$subarg};
	    }
	    
            my %tmphash;
	    %{$tmphash{$convert{$arg}}} = %subargs;
	    push @args_build, \%tmphash;
	}
	# ARRAY CONVERSION
	elsif (ref $args_make{$arg} eq 'ARRAY') {
	    warn "Warning: $arg - array conversion not supported\n";
	}
	# SCALAR CONVERSION
	#
	# One-dimensional hash values (scalars),
	# don't justify as SCALARS.
        elsif (ref $args_make{$arg} eq '') { 	
	    my %tmphash;
	    $tmphash{$convert{$arg}} = $args_make{$arg};
	    push @args_build, \%tmphash;
	}
	else { 
	    warn "Warning: $arg - unknown type of argument";
	}
    }    
    
    @args_build = @{_sort(\@args_build)} if %sorted_order;
    
    return \@args_build;
}

sub _insert_args { 
    return \%default_args;
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

    $Data::Dumper::Indent    = $DD_INDENT || 2;
    $Data::Dumper::Quotekeys = 0;
    $Data::Dumper::Sortkeys  = $DD_SORTKEYS;
    $Data::Dumper::Terse     = 1;
    
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
    
    $header =~ s/\$INTEND/$INTEND/g;
    
    _debug("\n$BUILD_PL written:\n");
    _debug($header);
    
    print $header;
}

sub _write_args {
    my($args) = @_;
    
    for my $arg (@$args) {
        # HASH OUTPUT 
        if ($arg =~ m#=> \{#o) {
	    # Remove redundant parentheses
	    $arg =~ s#^ \{ .*?\n (.*? \}) \s+ \} $#$1#osx;
	    
	    my @arg = @{_split_arg($arg)};
	    
	    # Gather whitespace up to hash key in order 
	    # to recreate native Dump() intendation.
	    my($whitespace) = $arg[0] =~ m#^ (\s+) (?: \w+)#ox;
	    my $shorten = length($whitespace);

            for my $arg (@arg) {
	        chomp($arg);
		
		# Remove additional whitespace
	        $arg =~ s#^ \s{$shorten} (.*) $#$1#ox;
		# Add quotes to hash keys within multiple hashes
		$arg =~ s#(\S+) => (\w+)#'$1' => $2#o;
		# Remove quotes on version numbers
		$arg =~ s# '(\d+)' (?: , | ) $#$1#ox;
		# Add comma where appropriate (version numbers, parentheses)
	        $arg .= ',' if ($arg =~ m#(?: \d+ | \}) $#ox);
		
		_debug("$INTEND$arg\n");
		
		print "$INTEND$arg\n";
            }
	}
	# SCALAR OUTPUT
	else {
	    chomp($arg);
	
	    # Remove redundant parentheses
            $arg =~ s#^ \{ \s+ (.*) \s+ \} $#$1#ox;
	    
	    _debug("$INTEND$arg\n");
	    
	    print "$INTEND$arg,\n";
	}
    }
}

sub _split_arg {
    my($arg) = @_;
    
    my @arg;
    
    # One element per each line        
    while ($arg =~ s#^ (.*?\n) (.*) $#$2#osx) {
        push @arg, $1;
    }
    
    return \@arg;
}

sub _write_footer {
    local $INTEND = $INTEND;
    chop($INTEND);
    
    $footer =~ s/\$INTEND/$INTEND/g;
    
    _debug($footer);
    
    print $footer;
}

sub _close_build_pl {
    close F_BUILD or
      die "Couldn't close $BUILD_PL: $!";
      
    select STDOUT; 
}

sub _debug { 
    print STDOUT @_ if $DEBUG; 
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
