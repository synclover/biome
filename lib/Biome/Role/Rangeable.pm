package Biome::Role::Rangeable;

use Biome::Role;
use Biome::Types qw(SequenceStrand);

has strand  => (
    isa     => SequenceStrand,
    is      => 'rw',
    default => 0,
    coerce  => 1
);

has start   => (
    is      => 'rw',
    isa     => 'Int',
);

has end     => (
    is      => 'rw',
    isa     => 'Int'
);

sub length {
    $_[0]->end - $_[0]->start + 1;
}

# returns true if strands are equal and non-zero
our %VALID_STRAND_TESTS = (
    'strong' => 1,
    'weak'   => 1,
    'ignore' => 1
    );

sub _strong {
    my ($s1, $s2) = ($_[0]->strand, $_[1]->strand);
    ($s1 != 0 && $s1 == $s2) ? 1 : 0
}

sub _weak {
    my ($s1, $s2) = ($_[0]->strand, $_[1]->strand);
    ($s1 == 0 || $s2 == 0 || $s1 == $s2) ? 1 : 0;
}

sub _ignore { 1 }

# works out what test to use for the strictness and returns true/false
# e.g. $r1->_testStrand($r2, 'strong')
sub _testStrand() {
    my ($r1, $r2, $comp) = @_;
    return 1 unless $comp;
    $r1->throw("$comp is not a supported strand test") unless exists $VALID_STRAND_TESTS{lc $comp};
    my $test = '_'.lc $comp;
    return $r1->$test($r2);
}

sub overlaps {
    my ($self, $other, $so) = @_;
    $self->_eval_ranges($other);
    ($self->_testStrand($other, $so)
        && !(($self->start() > $other->end() || $self->end() < $other->start())))
    ? 1 : 0;
}

sub contains {
    my ($self, $other, $so) = @_;
    $self->_eval_ranges($other);
    ($self->_testStrand($other, $so)
        && $other->start() >= $self->start() && $other->end() <= $self->end())
    ? 1 : 0;
}

sub equals {
    my ($self, $other, $so) = @_;
    $self->_eval_ranges($other);
    ($self->_testStrand($other, $so)
        && $self->start() == $other->start() && $self->end() == $other->end())
    ? 1 : 0;
}

# Original interface for this is a bit odd (accepts array or array ref with
# strand test). API also differs from union()
# Original code did not include appear to include self for some reason.

sub intersection {
    my ($self, $given, $so) = @_;
    $self->throw("Missing arg: you need to pass in another Range") unless $given;
    $so ||= 'ignore';
    my @ranges;
    ref($given) eq 'ARRAY' ? push( @ranges, @{$given}) : push(@ranges, $given);

    $self->_eval_ranges(@ranges);
    my $intersect;
    while (@ranges > 0) {
        unless ($intersect) {
            $intersect = $self;
        }

        my $compare = shift(@ranges);
        
        last if !defined $compare;
        
        if (!$compare->_testStrand($intersect, $so)) {
            return
        }

        my @starts = sort {$a <=> $b} ($intersect->start(), $compare->start());
        my @ends   = sort {$a <=> $b} ($intersect->end(), $compare->end());

        my $start = pop @starts; # larger of the 2 starts
        my $end = shift @ends;   # smaller of the 2 ends

        my $intersect_strand;    # strand for the intersection
        if (defined($intersect->strand) && defined($compare->strand) && $intersect->strand == $compare->strand) {
            $intersect_strand = $compare->strand;
        }
        else {
            $intersect_strand = 0;
        }

        if ($start > $end) {
            return;
        } else {
            $intersect = (blessed $self)->new(-start  => $start,
                                    -end    => $end,
                                    -strand => $intersect_strand);
        }
    }
    return $intersect;     
}

sub union {
    my ($self, $given, $so) = @_;
    
    # strand test doesn't matter here 
    
    $self->_eval_ranges(@$given);
    
    my @start = sort {$a <=> $b} map { $_->start() } ($self, @$given);
    my @end   = sort {$a <=> $b} map { $_->end()   } ($self, @$given);

    my $start = shift @start;
    while( !defined $start ) {
        $start = shift @start;
    }

    my $end = pop @end;

    my $union_strand = $self->strand;  # Strand for the union range object.

    for my $r (@$given) {
        if(!defined $r->strand || $union_strand ne $r->strand) {
            $union_strand = 0;
            last;
        }
    }
    return unless $start || $end;
    return (blessed $self)->new('-start' => $start,
                      '-end' => $end,
                      '-strand' => $union_strand
                      );
}

### Other methods

# should this return lengths or Range implementors?
# currently, returns integers, but I think Ranges would be more informative...

sub overlap_extent{
	my ($a,$b) = @_;

	$a->_eval_ranges($b);

	if( ! $a->overlaps($b) ) {
	    return ($a->clone,0,$b->clone);
	}

	my ($au,$bu) = (0, 0);
	if( $a->start < $b->start ) {
		$au = $b->start - $a->start;
	} else {
		$bu = $a->start - $b->start;
	}

	if( $a->end > $b->end ) {
		$au += $a->end - $b->end;
	} else {
		$bu += $b->end - $a->end;
	}

	my $intersect = $a->intersection($b);
	if( ! $intersect ) {
	    $a->warn("no intersection\n");
	    return ($au, 0, $bu);
	} else {
	    my $ie = $intersect->end;
	    my $is = $intersect->start;
	    return ($au,$ie-$is+1,$bu);
	}
}

sub subtract {
    my ($self, $range, $so) = @_;

    return $self unless $self->_testStrand($range, $so);

    $self->_eval_ranges($range);

    if (!$self->overlaps($range)) {
        return $self;  # no Range; maybe this should be Range?
    }

    # Subtracts everything (empty Range of length = 0 and strand = 0 
    if ($self->equals($range) || $range->contains($self)) {
        return (blessed $self)->new(-start => 0, -end => 0, -strand => 0);
    }

    my $int = $self->intersection($range, $so);
    my ($start, $end, $strand) = ($int->start, $int->end, $int->strand);
    
    #Subtract intersection from $self
    my @outranges = ();
    if ($self->start < $start) {
        push(@outranges, 
		 (blessed $self)->new(
                '-start'=> $self->start,
			    '-end'=>$start - 1,
			    '-strand'=>$self->strand,
			   ));
    }
    if ($self->end > $end) {
        push(@outranges, 
		 (blessed $self)->new('-start'=>$end + 1,
			    '-end'=>$self->end,
			    '-strand'=>$self->strand,
			   ));   
    }
    return @outranges;
}

# should be genericized for nonstranded Ranges.  I'm not sure about
# modifying the object in place...

sub offset_stranded {
    my ($self, $offset_fiveprime, $offset_threeprime) = @_;
    my ($offset_start, $offset_end) = $self->strand() eq -1 ?
        (- $offset_threeprime, - $offset_fiveprime) :
        ($offset_fiveprime, $offset_threeprime);
    $self->start($self->start + $offset_start);
    $self->end($self->end + $offset_end);
    return $self;
}

# may make this abstract...
sub to_string {
    my $self = shift;
    return sprintf("(%s, %s) strand=%d", $self->start, $self->end, $self->strand);
}

############## PRIVATE ##############

# called as instance method only; does slow things down a bit...
sub _eval_ranges {
    my ($self, @ranges) = @_;
    #$self->throw("start is undefined in calling instance") if !defined $self->start;
    #$self->throw("end is undefined in calling instance") if !defined $self->end;    
    for my $obj ($self, @ranges) {
        $self->throw("Not an object") unless ref($obj);
        $self->throw("start is undefined in instance ".$obj->to_string) if !defined $obj->start;
        $self->throw("end is undefined in instance ".$obj->to_string) if !defined $obj->end;
        $self->throw('Rangeable equality or set methods not '.
                     'implemented yet for fuzzy locations') if
            $self->does('Bio::Range::Segment') && $self->is_fuzzy;
    }
}

no Biome::Role;

1;

__END__

=head2 start

  Title   : start
  Usage   : $start = $range->start();
  Function: get/set the start of this range
  Returns : the start of this range
  Args    : optionally allows the start to be set
            using $range->start($start)

=cut

=head2 end

  Title   : end
  Usage   : $end = $range->end();
  Function: get/set the end of this range
  Returns : the end of this range
  Args    : optionally allows the end to be set
            using $range->end($end)

=cut

=head2 length

  Title   : length
  Usage   : $length = $range->length();
  Function: get/set the length of this range
  Returns : the length of this range
  Args    : optionally allows the length to be set
             using $range->length($length)

=cut

=head2 strand

  Title   : strand
  Usage   : $strand = $range->strand();
  Function: get/set the strand of this range
  Returns : the strandedness (-1, 0, +1)
  Args    : optionally allows the strand to be set
            using $range->strand($strand)

=cut

=head1 Boolean Methods

These methods return true or false. They throw an error if start and
end are not defined.

  $range->overlaps($otherRange) && print "Ranges overlap\n";

=head2 overlaps

  Title   : overlaps
  Usage   : if($r1->overlaps($r2)) { do stuff }
  Function: tests if $r2 overlaps $r1
  Args    : arg #1 = a range to compare this one to (mandatory)
            arg #2 = optional strand-testing arg ('strong', 'weak', 'ignore')
  Returns : true if the ranges overlap, false otherwise

=cut

=head2 contains

  Title   : contains
  Usage   : if($r1->contains($r2) { do stuff }
  Function: tests whether $r1 totally contains $r2
  Args    : arg #1 = a range to compare this one to (mandatory)
                 alternatively, integer scalar to test
            arg #2 = optional strand-testing arg ('strong', 'weak', 'ignore')
  Returns : true if the argument is totally contained within this range

=cut

=head2 equals

  Title   : equals
  Usage   : if($r1->equals($r2))
  Function: test whether $r1 has the same start, end, length as $r2
  Args    : arg #1 = a range to compare this one to (mandatory)
            arg #2 = optional strand-testing arg ('strong', 'weak', 'ignore')
  Returns : true if they are describing the same range

=cut

=head1 Geometrical methods

These methods do things to the geometry of ranges, and return
Bio::RangeI compliant objects or triplets (start, stop, strand) from
which new ranges could be built.

=head2 intersection

 Title   : intersection
 Usage   : ($start, $stop, $strand) = $r1->intersection($r2); OR
           ($start, $stop, $strand) = Bio::Range->intersection(\@ranges); OR
           my $containing_range = $r1->intersection($r2); OR
           my $containing_range = Bio::Range->intersection(\@ranges);
 Function: gives the range that is contained by all ranges
 Returns : undef if they do not overlap, or
           the range that they do overlap (in the form of an object
            like the calling one, OR a three element array)
 Args    : arg #1 = [REQUIRED] a range to compare this one to,
                    or an array ref of ranges
           arg #2 = optional strand-testing arg ('strong', 'weak', 'ignore')

=cut

=head2 union

   Title   : union
    Usage   : ($start, $stop, $strand) = $r1->union($r2);
            : ($start, $stop, $strand) = Bio::Range->union(@ranges);
              my $newrange = Bio::Range->union(@ranges);
    Function: finds the minimal Range that contains all of the Ranges
    Args    : a Range or list of Range objects
    Returns : the range containing all of the range
              (in the form of an object like the calling one, OR
              a three element array)

=cut

=head2 overlap_extent

 Title   : overlap_extent
 Usage   : ($a_unique,$common,$b_unique) = $a->overlap_extent($b)
 Function: Provides actual amount of overlap between two different
           ranges
 Example :
 Returns : array of values containing the length unique to the calling
           range, the length common to both, and the length unique to
           the argument range
 Args    : a range

=cut

=head2 disconnected_ranges

    Title   : disconnected_ranges
    Usage   : my @disc_ranges = Bio::Range->disconnected_ranges(@ranges);
    Function: finds the minimal set of ranges such that each input range
              is fully contained by at least one output range, and none of
              the output ranges overlap
    Args    : a list of ranges
    Returns : a list of objects of the same type as the input
              (conforms to RangeI)

=cut

=head2 offsetStranded

    Title    : offsetStranded
    Usage    : $rnge->ofsetStranded($fiveprime_offset, $threeprime_offset)
    Function : destructively modifies RangeI implementing object to
               offset its start and stop coordinates by values $fiveprime_offset and
               $threeprime_offset (positive values being in the strand direction).
    Args     : two integer offsets: $fiveprime_offset and $threeprime_offset
    Returns  : $self, offset accordingly.

=cut

=head2 subtract

  Title   : subtract
  Usage   : my @subtracted = $r1->subtract($r2)
  Function: Subtract range r2 from range r1
  Args    : arg #1 = a range to subtract from this one (mandatory)
            arg #2 = strand option ('strong', 'weak', 'ignore') (optional)
  Returns : undef if they do not overlap or r2 contains this RangeI,
            or an arrayref of Range objects (this is an array since some
            instances where the subtract range is enclosed within this range
            will result in the creation of two new disjoint ranges)

=cut

1;
