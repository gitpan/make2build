#! /usr/local/bin/perl

$VERSION = '0.11';

=head1 NAME

make2build - create a Build.PL derived from Makefile.PL

=head1 SYNOPSIS 

 ./make2build.pl    # In the top level directory of an 
                    # ExtUtils::MakeMaker based distribution 

=head1 DESCRIPTION

ExtUtils::MakeMaker has been a de-facto standard for the common distribution of Perl
modules; Module::Build is expected to supersede ExtUtils::MakeMaker in some time. 
The transition takes place slowly, as the converting process manually achieved 
is yet an uncommon practice. This parser is intended to ease the transition process.

=head1 OPTIONS

=head2 B<Globals>

=over 4

=item C<$MAKEFILE_PL>

The filename of the Makefile script. Defaults to F<Makefile.PL>.

=item C<$BUILD_PL>

The filename of the Build script. Defaults to F<Build.PL>.

=item C<$DEBUG>

Debugging. If set, created Build script will be printed to STDOUT.
Defaults to 0.

=item C<$LEN_INDENT>

Indentation (character width). Defaults to 3.

=item C<$DD_INDENT>

Data::Dumper indendation mode. Mode 0 will be disregarded in favor
of 2. Defaults to 2.

=item C<$DD_SORTKEYS>

Data::Dumper sort keys. Defaults to 1.

=back

=head2 B<Data section>

=over 4

=item B<argument conversion>

MakeMaker arguments followed by their Module::Build equivalents. 
Converted data structures preserve their native structure,
i.e. HASH -> HASH, etc.

 NAME         module_name
 PREREQ_PM    requires

=item B<default arguments>

Module::Build default arguments may be specified as key / value pairs. 
Arguments attached to multidimensional structures are unsupported.

 license               perl
 create_makefile_pl    passthrough

=item B<sorting order>

Module::Build arguments are sorted as enlisted herein. Additional arguments, 
that don't occur herein, are lower prioritized and will be inserted in 
unsorted order after preceedeingly sorted arguments.

 module_name
 license
 requires
 create_makefile_pl

=item B<prelude>

Code that preceeds Module::Build arguments.

 use Module::Build;

 my $b = Module::Build->new
 $INDENT(

=item B<epilogue>

Code that follows Module::Build arguments.

 $INDENT);

 $b->create_build_script;

=back

=head1 INTERNALS

=over 4

=item B<co-opting WriteMakefile()>

=item B<Data::Dumper>

=back

=head1 SEE ALSO

L<ExtUtils::MakeMaker>, L<Module::Build>	    

=cut

use strict;
use vars qw(
    $MAKEFILE_PL
    $BUILD_PL
    $DEBUG
    $LEN_INDENT
    $DD_INDENT
    $DD_SORTKEYS
);
use warnings; 
no warnings 'redefine';
use Data::Dumper;
use ExtUtils::MakeMaker;

our ($INDENT, %Data);
     

$MAKEFILE_PL    = 'Makefile.PL';
$BUILD_PL       = 'Build.PL';

$DEBUG          = 0;
$LEN_INDENT     = 3;

# Data::Dumper
$DD_INDENT      = 2;
$DD_SORTKEYS    = 1;


*ExtUtils::MakeMaker::WriteMakefile = \&_convert;

_run_makefile();

sub _run_makefile {
    -e $MAKEFILE_PL
      ? do $MAKEFILE_PL
      : die "No $MAKEFILE_PL found\n";
}

sub _convert {
    local %Data; 
    
    _get_data();
    
    print "Converting $MAKEFILE_PL -> $BUILD_PL\n";
    
    _write( _dump( &_build_args ) );
}

sub _get_data {
    local $/ = '1;';
    local $_ = <DATA>;
                                        #  # description
    my @data = split /#\s+.*\s+-\n/;    #  -
    
    (undef) = shift @data;              # Superfluos items			
    chomp $data[-1]; $/ = "\n";
    chomp $data[-1]; 
    
    $Data{build}           = { split /\s+/, shift @data };
    $Data{default_args}    = { split /\s+/, shift @data };
    $Data{sort_order}      = [ split /\s+/, shift @data ];
   ($Data{header}, 
    $Data{footer})         =                      @data;
}

sub _build_args { 
    my %make = @_;                         # Makefile.PL arguments
    my @build_args = @{_insert_args()};      
    
    for my $arg (keys %make) {
        next unless $Data{build}->{$arg};
	
        if (ref $make{$arg} eq 'HASH') {                                ### HASH CONVERSION
	    my %subargs;   
	    for my $subarg (keys %{$make{$arg}}) {
	        $subargs{$subarg} = $make{$arg}{$subarg};
	    }
	    
            my %tmphash;
	    %{$tmphash{$Data{build}->{$arg}}} = %subargs;  
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
	    $tmphash{$Data{build}->{$arg}} = $make{$arg};
	    push @build_args, \%tmphash;
	}
	else { 
	    warn "Warning: $arg - unknown type of argument\n";
	}
    }
    
    _sort( \@build_args )    if @{$Data{sort_order}};
    
    return \@build_args;
}

sub _insert_args {
    my @insert_args;

    while (my ($arg, $value) = each %{$Data{default_args}}) {
        my %tmphash;
	$tmphash{$arg} = $value;
	push @insert_args, \%tmphash;
    }
    
    return \@insert_args;
}

sub _sort {
    my ($args) = @_;
    
    my %sort_order;
    {
        my %have_args = map { keys %$_ => 1 } @$args;
	
        my $i = 0;
        %sort_order = map {                               # Filter sort items, that we didn't receive as args,
            $_ => $i++                                    # and map the rest to according array indexes.
        } (grep $have_args{$_}, @{$Data{sort_order}});    
    }  
    
    my ($sorted, @unsorted);
    do {
        $sorted = 1;
	
	SORT:
        for (my $i = 0; $i < @$args; $i++) {   
            my ($arg) = keys %{$args->[$i]};
	    
	    unless (defined $sort_order{$arg}) {
	       push @unsorted, splice( @$args, $i, 1 );
	    }
	    
            if ($i != $sort_order{$arg}) {
                $sorted = 0;

	        push @$args,                               # Move element $i to pos $Sort_order{$arg}
		  splice( @$args, $sort_order{$arg}, 1,    # and the element at $Sort_order{$arg} to 
		    splice( @$args, $i, 1 ) );             # the end. 
		    
		last SORT;    
	    }
        }
    } until ($sorted);
    
    push @$args, @unsorted;  
}

sub _dump {
    my ($args) = @_;

    $Data::Dumper::Indent       = $DD_INDENT || 2;
    $Data::Dumper::Quotekeys    = 0;
    $Data::Dumper::Sortkeys     = $DD_SORTKEYS;
    $Data::Dumper::Terse        = 1;
    
    my $d = Data::Dumper->new( $args );
    
    return [ $d->Dump ];
}

sub _write { 
    local $INDENT = ' ' x $LEN_INDENT;
    
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
    chop( my $INDENT = $INDENT );
    
    $Data{header} =~ s/(\$[A-Z]+)/$1/eeg;
    
    _debug( "\n$BUILD_PL written:\n" );
    _debug( $Data{header} );
    
    print $Data{header}; 
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
	    my $shorten = length $whitespace;                    # to recreate native Dump() intendation.
	    
            for my $line (@lines) {
	        chomp $line;
		
	        $line =~ s/^ \s{$shorten} (.*) $/$1/ox;          # Remove additional whitespace
		$line =~ s/(\S+) => (\w+)/'$1' => $2/o;          # Add quotes to hash keys within multiple hashes
		#$line =~ s/'(\d+)' [, ] $/$1/ox;                # Remove quotes on version numbers
	        $line .= ','    if ($line =~ /[\d+ \}] $/ox);    # Add comma where appropriate (version numbers, parentheses)
		
		_debug( "$INDENT$line\n" );
		
		print "$INDENT$line\n";
            }
	}
	else {                                                   ### SCALAR OUTPUT
	    chomp $arg;
	    
            $arg =~ s/^ \{ \s+ (.*) \s+ \} $/$1/ox;              # Remove redundant parentheses
	    
	    _debug( "$INDENT$arg,\n" );
	    
	    print "$INDENT$arg,\n";
	}
    }
}

sub _write_footer {
    chop( my $INDENT = $INDENT );
    
    $Data{footer} =~ s/(\$[A-Z]+)/$1/eeg;
    
    _debug( $Data{footer} );
    
    print $Data{footer};
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
 
# argument conversion 
-
NAME                  module_name
PREREQ_PM             requires
 
# default arguments 
-
license               perl
create_makefile_pl    passthrough
 
# sorting order 
-
module_name
license
requires
create_makefile_pl
 
# prelude 
-

use Module::Build;

my $b = Module::Build->new
$INDENT(
# epilogue 
-
$INDENT);
  
$b->create_build_script;

1;
