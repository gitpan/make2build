#! /usr/local/bin/perl

$VERSION = '0.04';

use strict;
#use warnings; 
#no warnings 'redefine';
use Data::Dumper;
use ExtUtils::MakeMaker;

our (
     %Build,
     %Default_args,
     @Sort_order,
     $Header,
     $Footer,
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
    local (
           %Build,           # Conversion table 
	   %Default_args,
           @Sort_order, 
	   $Header,
	   $Footer,
    );
    
    _get_data();

    print "Converting $MAKEFILE_PL -> $BUILD_PL\n";
    
    _write( _dump( &_build_args ) );
}

sub _get_data {
    local $/ = '1;';
    local $_ = <DATA>;
    
    my $regexp = qr{#\s+.*\s+?-\s+?\n};    #  # description
    my @data = split /$regexp/;            #  -
    
    shift @data;                           # Superfluos items			
    chomp $data[-1]; $/ = "\n";            
    chomp $data[-1];                       
    
    %Build           = split /\s+/, shift @data;
    %Default_args    = split /\s+/, shift @data;
    @Sort_order      = split /\s+/, shift @data;
   ($Header, 
    $Footer)         =                    @data;
}

sub _build_args { 
    my %make = @_;                           # Makefile.PL arguments
    my @build_args = @{ _insert_args() };  
    
    for my $arg (keys %make) {
        next unless $Build{$arg};
	
        if (ref $make{$arg} eq 'HASH') {                                ### HASH CONVERSION
 	    my (%subargs, $count_subargs);  
	    my ($total_subargs) = %{ $make{$arg} } =~ /^(.)/;    
	    
	    for my $subarg (keys %{ $make{$arg} }) {
	        $subargs{$subarg} = $make{$arg}{$subarg};
	    }
	    
            my %tmphash;
	    
	    %{ $tmphash{ $Build{$arg} } } = %subargs;  
	    push @build_args, \%tmphash;
	}
	elsif (ref $make{$arg} eq 'ARRAY') {                            ### ARRAY CONVERSION
	    warn "Warning: $arg - array conversion not supported\n";
	}
	#
	# One-dimensional hash values (scalars),
	# don't justify as SCALARS.
	#
        elsif (ref $make{$arg} eq '') { 	                        ### SCALAR CONVERSION
	    my %tmphash;
	    
	    $tmphash{ $Build{$arg} } = $make{$arg};
	    push @build_args, \%tmphash;
	}
	else { 
	    warn "Warning: $arg - unknown type of argument\n";
	}
    }   
    undef %Build; 
    
    _sort( \@build_args )    if @Sort_order;
    
    return \@build_args;
}

sub _insert_args {
    my @insert_args;

    while (my ($arg, $value) = each %Default_args) {
        my %tmphash;
	
	$tmphash{$arg} = $value;
	push @insert_args, \%tmphash;
    }
    undef %Default_args;
    
    return \@insert_args;
}

sub _sort {
    my ($args) = @_;
    
    my %sort_order;
    {
        my %have_args = map { keys %$_ => 1 } @$args;
	
        my $i = 0;
        %sort_order = map {    # Filter sort items, that we didn't receive as args,
            $_ => $i++         # and map the rest to according array indexes.
        } 
        (grep $have_args{$_}, @Sort_order);    
	
	undef @Sort_order;
    }    
    
    my ($sorted, @unsorted);
    do {
        $sorted = 1;
	
	ITER:
        for (my $i = 0; $i < @$args; $i++) {   
            my ($arg) = keys %{ $args->[$i] };
	    
	    unless (defined $sort_order{$arg}) {
	       push @unsorted, splice( @$args, $i, 1 );
	    }
	    
            if ($i != $sort_order{$arg}) {
                $sorted = 0;

	        push @$args,                               # Move element $i to pos $Sort_order{$arg}
		  splice( @$args, $sort_order{$arg}, 1,    # and the element at $Sort_order{$arg} to 
		    splice( @$args, $i, 1 ) );             # the end. 
		    
		last ITER;    
	    }
        }
    } 
    until ($sorted);
    
    push @$args, @unsorted;  
}

sub _dump {
    my ($args) = @_;

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
    chop( $INTEND );
    
    $Header =~ s/(\$[A-Z]+)/$1/eeg;
    
    _debug( "\n$BUILD_PL written:\n" );
    _debug( $Header );
    
    print $Header; 
    undef $Header;
}

sub _write_args {
    my ($args) = @_;
    
    for my $arg (@$args) {                                        
        if ($arg =~ /\Q => {/ox) {                               ### HASH OUTPUT
	    $arg =~ s/^ \{ .*?\n (.*? \}) \s+ \} $/$1/osx;       # Remove redundant parentheses
	    
	    my @lines;        
            while ($arg =~ s/^ (.*?\n) (.*) $/$2/osx) {          # One element per each line
                push @lines, $1;
            };
	    
	    my ($whitespace) = $lines[0] =~ /^ (\s+) \w+/ox;     # Gather whitespace up to hash key in order 
	    my $shorten = length( $whitespace );                 # to recreate native Dump() intendation.
	    
            for my $line (@lines) {
	        chomp( $line );
		
	        $line =~ s/^ \s{$shorten} (.*) $/$1/ox;          # Remove additional whitespace
		$line =~ s/(\S+) => (\w+)/'$1' => $2/o;          # Add quotes to hash keys within multiple hashes
		$line =~ s/'(\d+)' [, ] $/$1/ox;                 # Remove quotes on version numbers
	        $line .= ','    if ($line =~ /[\d+ \}] $/ox);    # Add comma where appropriate (version numbers, parentheses)
		
		_debug( "$INTEND$line\n" );
		
		print "$INTEND$line\n";
            }
	}
	else {                                                   ### SCALAR OUTPUT
	    chomp( $arg );
	    
            $arg =~ s/^ \{ \s+ (.*) \s+ \} $/$1/ox;              # Remove redundant parentheses
	    
	    _debug( "$INTEND$arg,\n" );
	    
	    print "$INTEND$arg,\n";
	}
    }
}

sub _write_footer {
    local $INTEND = $INTEND;
    chop( $INTEND );
    
    $Footer =~ s/(\$[A-Z]+)/$1/eeg;
    
    _debug( $Footer );
    
    print $Footer;
    undef $Footer;
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
NAME                  module_name
PREREQ_PM             requires
 
# default args 
- 
license               perl
create_makefile_pl    passthrough
 
# sort order 
- 
module_name
license
requires
create_makefile_pl
 
# header 
- 

use Module::Build;

my $b = Module::Build->new
$INTEND(
# footer 
- 
$INTEND);
  
$b->create_build_script;

1;
__END__

=head1 NAME

make2build - generate a Build.PL derived from Makefile.PL

=head1 SYNOPSIS 

 ./make2build.pl    # In the root directory of a ExtUtils::MakeMaker 
                    # (or F<Makefile.PL>) based distribution 

=head1 DESCRIPTION

-

=head1 SEE ALSO

L<ExtUtils::MakeMaker>, L<Module::Build>

=head1 AUTHOR

Steven Schubiger		    

=cut
