#! /usr/bin/perl

our $VERSION = '0.17';
our $NAME = 'make2build';

=head1 NAME

make2build - create a Build.PL derived from Makefile.PL

=head1 SYNOPSIS 

 ./make2build.pl    # In the root directory of an 
                    # ExtUtils::MakeMaker based distribution 

=head1 DESCRIPTION

C<ExtUtils::MakeMaker> has been a de-facto standard for the common distribution of Perl
modules; C<Module::Build> is expected to supersede C<ExtUtils::MakeMaker> in some time.
 
The transition takes place slowly, as the converting process manually achieved 
is yet an uncommon practice. This F<Makefile.PL> parser is intended to ease the 
transition process.

=head1 ARGUMENTS

=head2 B<Globals>

=over 4

=item C<$MAKEFILE_PL>

The filename of the Makefile script. Defaults to F<Makefile.PL>.

=item C<$BUILD_PL>

The filename of the Build script. Defaults to F<Build.PL>.

=item C<$VERBOSE>

Verbose mode. If set, created Build script will be printed to STDERR.
Defaults to 0.

=item C<$LEN_INDENT>

Indentation (character width). Defaults to 3.

=item C<$DD_INDENT>

C<Data::Dumper> indendation mode. Mode 0 will be disregarded in favor
of 2. Defaults to 2.

=item C<$DD_SORTKEYS>

C<Data::Dumper> sort keys. Defaults to 1.

=back

=head2 B<Data section>

=over 4

=item B<argument conversion>

C<ExtUtils::MakeMaker> arguments followed by their C<Module::Build> equivalents. 
Converted data structures preserve their native structure,
i.e. HASH -> HASH, etc.

 NAME                  module_name
 DISTNAME              dist_name
 VERSION               dist_version
 VERSION_FROM          dist_version_from
 PREREQ_PM             requires
 PM                    pm_files
 CCFLAGS               extra_compiler_flags
 SIGN                  sign
 ABSTRACT              dist_abstract
 AUTHOR                dist_author

=item B<default arguments>

C<Module::Build> default arguments may be specified as key / value pairs. 
Arguments attached to multidimensional structures are unsupported.

 recommends	       HASH
 build_requires        HASH
 conflicts	       HASH
 license               unknown
 create_makefile_pl    passthrough
 
Value may be either a string or of type SCALAR, ARRAY, HASH.

=item B<sorting order>

C<Module::Build> arguments are sorted as enlisted herein. Additional arguments, 
that don't occur herein, are lower prioritized and will be inserted in 
unsorted order after preceedeingly sorted arguments.

 module_name
 dist_name
 dist_version
 dist_version_from
 requires
 recommends
 build_requires
 conflicts
 pm_files
 extra_compiler_flags
 sign
 license
 create_makefile_pl
 dist_abstract
 dist_author

=item B<begin code>

Code that preceeds converted C<Module::Build> arguments.

 use Module::Build;

 my $b = Module::Build->new
 $INDENT(

=item B<end code>

Code that follows converted C<Module::Build> arguments.

 $INDENT);

 $b->create_build_script;

=back

=head1 INTERNALS

=over 4

=item B<co-opting C<WriteMakefile()>>

In order to convert arguments, a typeglob from C<WriteMakefile()> to an internal
sub will be set; subsequently Makefile.PL will be executed and the
arguments are then accessible to the internal sub.

=item B<Data::Dumper>

Converted C<ExtUtils::MakeMaker> arguments will be dumped by 
C<Data::Dumper's> C<Dump()> and are then furtherly processed.

=back

=head1 SEE ALSO

L<ExtUtils::MakeMaker>, L<Module::Build>, L<http://www.makemaker.org/wiki/index.cgi?ModuleBuildConversionGuide>

=head1 AUTHOR

Steven Schubiger <steven@accognoscere.org>	    

=cut

use strict;
use vars qw(
    $MAKEFILE_PL
    $BUILD_PL
    $VERBOSE
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

$VERBOSE        = 0;
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
    _write(_dump(&_build_args));
}

sub _get_data {
    local $/ = '1;';
    
    my @data = do {
        local $_ = <DATA>;    #  # description       
	split /#\s+.*\s+-\n/; #  -     
    };
    
    # superfluosity
    (undef) = shift @data;         			
    chomp $data[-1]; $/ = "\n";
    chomp $data[-1]; 
    
    $Data{build}           = { split /\s+/, shift @data };
    $Data{default_args}    = { split /\s+/, shift @data };
    $Data{sort_order}      = [ split /\s+/, shift @data ];
   ($Data{begin}, 
    $Data{end})            =                      @data;
}

sub _build_args {
    # Makefile.PL arguments 
    my %make = @_;                         
    my @build_args = @{_insert_args()};      
    
    for my $arg (keys %make) {
        next unless $Data{build}->{$arg};
	
	### HASH CONVERSION
        if (ref $make{$arg} eq 'HASH') {                                
	    my %subargs;   
	    for my $subarg (keys %{$make{$arg}}) {
	        $subargs{$subarg} = $make{$arg}{$subarg};
	    }
	    
            my %tmphash;
	    %{$tmphash{$Data{build}->{$arg}}} = %subargs;  
	    push @build_args, \%tmphash;
	}
	### ARRAY CONVERSION
	elsif (ref $make{$arg} eq 'ARRAY') {                            
	    warn "Warning: $arg - array conversion not supported\n";    
	}
	# One-dimensional hash values (scalars),
	# don't justify as SCALARS.
	###
	### SCALAR CONVERSION
        elsif (ref $make{$arg} eq '') { 	                        
	    my %tmphash;
	    $tmphash{$Data{build}->{$arg}} = $make{$arg};
	    push @build_args, \%tmphash;
	}
	### UNKNOWN
	else { 
	    warn "Warning: $arg - unknown type of argument\n";
	}
    }
    
    _sort(\@build_args) if @{$Data{sort_order}};
    
    return \@build_args;
}

sub _insert_args {
    my @insert_args;

    while (my ($arg, $value) = each %{$Data{default_args}}) {
        $value = {} if $value eq 'HASH';
	$value = [] if $value eq 'ARRAY';
	$value = '' if $value eq 'SCALAR';
	
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
	
	# Filter sort items, that we didn't receive as args,
	# and map the rest to according array indexes.
        my $i;
        %sort_order = map {                             
            $_ => $i++                                  
        } grep $have_args{$_}, @{$Data{sort_order}};    
    }  
    
    my ($is_sorted, @unsorted);
    do {
        $is_sorted = 1;
	
          SORT: for (my $i = 0; $i < @$args; $i++) {   
              my ($arg) = keys %{$args->[$i]};
	    
	      unless (defined $sort_order{$arg}) {
	          push @unsorted, splice(@$args, $i, 1);
	          next;
	      }
	    
              if ($i != $sort_order{$arg}) {
                  $is_sorted = 0;
                  # Move element $i to pos $Sort_order{$arg}
		  # and the element at $Sort_order{$arg} to
		  # the end. 
	          push @$args,                              
		    splice(@$args, $sort_order{$arg}, 1,    
		      splice(@$args, $i, 1));                
		    
                  last SORT;    
	      }
          }
    } until ($is_sorted);
    
    push @$args, @unsorted;  
}

sub _dump {
    my ($args) = @_;

    $Data::Dumper::Indent       = $DD_INDENT || 2;
    $Data::Dumper::Quotekeys    = 0;
    $Data::Dumper::Sortkeys     = $DD_SORTKEYS;
    $Data::Dumper::Terse        = 1;
    
    my $d = Data::Dumper->new($args);
    
    return [ $d->Dump ];
}

sub _write { 
    my $INDENT = ' ' x $LEN_INDENT;
    # @_ & $INDENT -> _write_args
    push @_, $INDENT; 
    
    # Fool 'once' warnings
    my $fh = \*F_BUILD; 
       $fh = \*F_BUILD;
    my $selold = _open_build_pl($fh);

    _write_begin($INDENT);
   &_write_args;
    _write_end($INDENT);
    
    _close_build_pl($fh, $selold);
}

sub _open_build_pl {
    my ($fh) = @_;
    
    open($fh, ">$BUILD_PL") or 
      die "Couldn't open $BUILD_PL: $!";
      
    return select $fh;
}

sub _write_begin {
    my ($INDENT) = @_;  
    $INDENT = substr($INDENT, 0, length($INDENT)-1);
    
    $Data{begin} =~ s/(\$[A-Z]+)/$1/eeg;
    
    _do_verbose("\n$BUILD_PL written:\n");
    _do_verbose($Data{begin});
    
    print "## Created by $NAME $VERSION\n";
    print $Data{begin};
}

sub _write_args {
    my ($args, $INDENT) = @_;
    
    for my $arg (@$args) {
        ### HASH OUTPUT                                        
        if ($arg =~ /\Q => {/ox) {                               
	    # Remove redundant parentheses
	    $arg =~ s/^ \{ .*?\n (.*? \}) \s+ \} $/$1/osx;       
	    
	    # One element per each line
	    my @lines;        
            while ($arg =~ s/^ (.*?\n) (.*) $/$2/osx) {          
                push @lines, $1;
            };
	    
	    # Gather whitespace up to hash key in order
	    # to recreate native Dump() indentation. 
	    my ($whitespace) = $lines[0] =~ /^ (\s+) \w+/ox;
	    my $shorten = length $whitespace;                    
	    
            for my $line (@lines) {
	        chomp $line;
		
		# Remove additional whitespace
	        $line =~ s/^ \s{$shorten} (.*) $/$1/ox;
		# Add quotes to hash keys within multiple hashes          
		$line =~ s/(\S+) => (\w+)/'$1' => $2/o;
		# Add comma where appropriate (version numbers, parentheses)          
	        $line .= ',' if ($line =~ /[\d+ \}] $/ox);       
		
		_do_verbose("$INDENT$line\n");
		print       "$INDENT$line\n";
            }
	}
	### SCALAR OUTPUT
	else {                                                   
	    chomp $arg;
	    # Remove redundant parentheses
            $arg =~ s/^ \{ \s+ (.*) \s+ \} $/$1/ox;              
	    
	    _do_verbose("$INDENT$arg,\n");
	    print       "$INDENT$arg,\n";
	}
    }
}

sub _write_end {
    my ($INDENT) = @_;
    $INDENT = substr($INDENT, 0, length($INDENT)-1);
    
    $Data{end} =~ s/(\$[A-Z]+)/$1/eeg;
    
    _do_verbose($Data{end});
    print       $Data{end};
}

sub _close_build_pl {
    my ($fh, $selold) = @_;

    close($fh) or
      die "Couldn't close $BUILD_PL: $!";
      
    select $selold; 
}

sub _do_verbose { 
    warn @_ if $VERBOSE; 
}

__DATA__
 
# argument conversion 
-
NAME                  module_name
DISTNAME              dist_name
VERSION               dist_version
VERSION_FROM          dist_version_from
PREREQ_PM             requires
PM                    pm_files
CCFLAGS               extra_compiler_flags
SIGN                  sign
ABSTRACT              dist_abstract
AUTHOR                dist_author
 
# default arguments 
-
recommends	      HASH
build_requires        HASH
conflicts	      HASH
license               unknown
create_makefile_pl    passthrough
 
# sorting order 
-
module_name
dist_name
dist_version
dist_version_from
requires
recommends
build_requires
conflicts
pm_files
extra_compiler_flags
sign
license
create_makefile_pl
dist_abstract
dist_author

# begin code 
-

use Module::Build;

my $b = Module::Build->new
$INDENT(
# end code 
-
$INDENT);
  
$b->create_build_script;

1;
