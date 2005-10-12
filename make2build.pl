#!/usr/bin/perl

our $VERSION = '0.18_02';
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

=item C<$MANIFEST>

The filename of the MANIFEST file. Defaults to F<MANIFEST>.

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
 clean->FILES          add_to_cleanup

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

Steven Schubiger <sts@accognoscere.org>	    

=cut

use strict;
use warnings; 
no warnings 'redefine';

use Data::Dumper;
use ExtUtils::MakeMaker;

our ($MAKEFILE_PL,
     $BUILD_PL,
     $MANIFEST,
     $VERBOSE,
     $LEN_INDENT,
     $DD_INDENT,
     $DD_SORTKEYS,
     $INDENT, 
     %Data);
     
$MAKEFILE_PL    = 'Makefile.PL';
$BUILD_PL       = 'Build.PL';
$MANIFEST	= 'MANIFEST';

$VERBOSE        = 0;
$LEN_INDENT     = 3;

# Data::Dumper
$DD_INDENT      = 2;
$DD_SORTKEYS    = 1;

*ExtUtils::MakeMaker::WriteMakefile = \&convert;

run_makefile();

sub run_makefile {
    -e $MAKEFILE_PL
      ? do $MAKEFILE_PL
      : die "No $MAKEFILE_PL found\n";
}

sub convert {
    local %Data; 
    get_data();
    print "Converting $MAKEFILE_PL -> $BUILD_PL\n";
    my $args = &build_args;
    $args = output($args);
    create($args);
    add_to_manifest() if -e 'MANIFEST';
}

sub get_data {
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

    # allow for embedded values such as clean => { FILES => '' }
    foreach my $arg (keys %{$Data{build}}) {
        if (index($arg, '.') > 0) {
	    my @path = split(/\./, $arg);
	    my $value = $Data{build}->{$arg};
	    my $current = $Data{build};
	    while (@path) {
	        my $key = shift(@path);
		$current->{$key} ||= @path ? {} : $value;
		$current = $current->{$key};
	    }
	}
    }
}

sub build_args {
    # Makefile.PL arguments 
    my %make = @_;                         
    my @build_args = @{insert_args()};      
    for my $arg (keys %make) {
        next unless $Data{build}->{$arg};
	# Hash conversion
        if (ref($make{$arg}) eq 'HASH') {                                
	    if (ref($Data{build}->{$arg}) eq 'HASH') {
		# embedded structure
		my @iterators = ();
		my $current = $Data{build}->{$arg};
		my $value = $make{$arg};
		push @iterators, iterator($current, $value, keys %$current);
		while (@iterators) {
		    my $iterator = shift(@iterators);
		    while (($current, $value) = $iterator->()) {
			if (ref($current) eq 'HASH') {
			    push @iterators, iterator($current, $value, keys %$current);
			} else {
			    if (substr($current, 0, 1) eq '@') {
				my $attr = substr($current, 1);
			        if (ref($value) eq 'ARRAY') {
				    push @build_args, { $attr => $value };
				} else {
				    push @build_args, { $attr => [ split ' ', $value ] };
				}
			    } else {
			        push @build_args, { $current => $value };
			    }
			}
		    }
		}
	    } else {
		# flat structure
		my %subargs;   
		for my $subarg (keys %{$make{$arg}}) {
		    $subargs{$subarg} = $make{$arg}{$subarg};
		}
		my %tmphash;
		%{$tmphash{$Data{build}->{$arg}}} = %subargs;  
		push @build_args, \%tmphash;
	    }
	} elsif (ref $make{$arg} eq 'ARRAY') { # Array conversion                           
	    warn "Warning: $arg - array conversion not supported\n";    
	} elsif (ref $make{$arg} eq '') { # One-dimensional hash values (scalars),
	    my %tmphash;                  # don't justify as SCALARS - Scalar conversion.
	    $tmphash{$Data{build}->{$arg}} = $make{$arg};                     
	    push @build_args, \%tmphash;
	} else { # Unknown type
	    warn "Warning: $arg - unknown type of argument\n";
	}
    }
    sort_args(\@build_args) if @{$Data{sort_order}};
    return \@build_args;
}

sub iterator {
    my $build = shift;
    my $make  = shift;
    my @queue = @_;
    return sub {
        my $key = shift(@queue) || return;
	return $build->{$key}, $make->{$key};
    }
}

sub insert_args {
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

sub sort_args {
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

sub output {
    my ($args) = @_;
    
    $Data::Dumper::Indent       = $DD_INDENT || 2;
    $Data::Dumper::Quotekeys    = 0;
    $Data::Dumper::Sortkeys     = $DD_SORTKEYS;
    $Data::Dumper::Terse        = 1;
    
    my $d = Data::Dumper->new($args);
    return [ $d->Dump ];
}

sub create { 
    my $INDENT = ' ' x $LEN_INDENT;
    # @_ & $INDENT -> _write_args
    push @_, $INDENT; 
    
    # Fool 'once' warnings
    my $fh = \*F_BUILD; 
       $fh = \*F_BUILD;
       
    my $selold = open_build_pl($fh);
    write_begin($INDENT);
   &write_args;
    write_end($INDENT);
    close_build_pl($fh, $selold);
    
    print "Conversion done\n";
}

sub open_build_pl {
    my ($fh) = @_;
    open($fh, ">$BUILD_PL") or 
      die "Couldn't open $BUILD_PL: $!";
    return select $fh;
}

sub write_begin {
    my ($INDENT) = @_;  
    $INDENT = substr($INDENT, 0, length($INDENT)-1);
    $Data{begin} =~ s/(\$[A-Z]+)/$1/eeg;
    
    do_verbose("\n$BUILD_PL written:\n");
    do_verbose($Data{begin});  
    print "# Note: this file was auto-generated by $NAME $VERSION\n";
    print $Data{begin};
}

sub write_args {
    my ($args, $INDENT) = @_;
    for my $arg (@$args) {
        # Hash output                       
        if ($arg =~ /=> [\{\[]/o) {
	    # Remove redundant parentheses
	    my $eval = '$arg =~ /=> \{/o';
	    my $re_eval = qr/(?{ eval $eval ? '\}' : '\]' })/o;                         
	    $arg =~ s/^\{.*?\n(.*(??{ $re_eval }))\s+\}\s+$/$1/os;
	    
	    # One element per each line
	    my @lines;        
            while ($arg =~ s/^(.*?\n)(.*)$/$2/os) {          
                push @lines, $1;
            };
	    # Gather whitespace up to hash key in order
	    # to recreate native Dump() indentation. 
	    my ($whitespace) = $lines[0] =~ /^(\s+)\w+/o;
	    my $shorten = length $whitespace;
	    
            for my $line (@lines) {
	        chomp $line;
		# Remove additional whitespace
	        $line =~ s/^\s{$shorten}(.*)$/$1/o;
		# Add comma where appropriate (version numbers, parentheses)          
	        $line .= ',' if $line =~ /[\d+\}\]]$/o;
		
		do_verbose("$INDENT$line\n");
		print "$INDENT$line\n";
            }
	} else { # Scalar output                                                 
	    chomp $arg;
	    # Remove redundant parentheses
            $arg =~ s/^\{\s+(.*?)\s+\}$/$1/os;
	    
	    do_verbose("$INDENT$arg,\n");
	    print "$INDENT$arg,\n";
	}
    }
}

sub write_end {
    my ($INDENT) = @_;
    $INDENT = substr($INDENT, 0, length($INDENT)-1);
    $Data{end} =~ s/(\$[A-Z]+)/$1/eeg;
    
    do_verbose($Data{end});
    print $Data{end};
}

sub close_build_pl {
    my ($fh, $selold) = @_;
    close($fh);
    select($selold); 
}

sub do_verbose {
    print @_ if $VERBOSE;
}

sub add_to_manifest {
    open(my $fh, "<$MANIFEST") or die "Could not open $MANIFEST: $!\n";
    my @manifest = <$fh>;
    close($fh);
    
    my %have;
    my @files = @manifest;
    chomp @files;
    $have{$_} = 1 for @files;
    
    unless ($have{$BUILD_PL}) {
        unshift @manifest, "$BUILD_PL\n";
        open($fh, ">$MANIFEST") or die "Could not open $MANIFEST: $!\n";
        print $fh sort @manifest;
        close($fh);
	print "Added $BUILD_PL to $MANIFEST\n";
    }
}
 

__DATA__
 
# argument conversion 
-
NAME                  module_name
DISTNAME              dist_name
ABSTRACT              dist_abstract
AUTHOR                dist_author
VERSION               dist_version
VERSION_FROM          dist_version_from
PREREQ_PM             requires
PM                    pm_files
CCFLAGS               extra_compiler_flags
SIGN                  sign
clean.FILES           @add_to_cleanup
 
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
dist_abstract
dist_author
dist_version
dist_version_from
requires
recommends
build_requires
conflicts
pm_files
add_to_cleanup
extra_compiler_flags
sign
license
create_makefile_pl

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
