package Biome::Factory::FTLocationFactory;

use Biome;

#with 'Biome::Role::ManageTypes';

my $LOCREG;

# the below is an optimized regex obj. from J. Freidl's Mastering Reg Exp.
$LOCREG = qr{
            (?>
            [^()]+
            |
            \(
            (??{$LOCREG})
            \)
            )*
            }x;     

has coordinate_policy   => (
    is          => 'ro',
    does        => 'Biome::Location::Role::CoordinatePolicy',
    #required    => 1,
);

sub from_string {
    my ($self,$locstr,$op) = @_;
    my $loc;
    
    $self->debug("$locstr\n");
    
    # $op for operator (error handling)
    
    # run on first pass only
    # Note : These location types are now deprecated in GenBank (Oct. 2006)
    if (!defined($op)) {
        # convert all (X.Y) to [X.Y]
        $locstr =~ s{\((\d+\.\d+)\)}{\[$1\]}g;
        # convert ABC123:(X..Y) to ABC123:[X..Y]
        # we should never see the above
        $locstr =~ s{:\((\d+\.{2}\d+)\)}{:\[$1\]}g;
    }
    
    if ($locstr =~ m{(.*?)\(($LOCREG)\)(.*)}o) { # any matching parentheses?

        my ($beg, $mid, $end) = ($1, $2, $3);
        my (@sublocs) = (split(q(,),$beg), $mid, split(q(,),$end));
        
        my @loc_objs;
        my $loc_obj;
        
        SUBLOCS:
        while (@sublocs) {
            my $subloc = shift @sublocs;
            next if !$subloc;
            my $oparg = ($subloc eq 'join'   || $subloc eq 'bond' ||
                         $subloc eq 'order'  || $subloc eq 'complement') ? $subloc : undef;
            # has operator, requires further work (recurse)
            if ($oparg) {
                my $sub = shift @sublocs;
                # simple split operators (no recursive calls needed)
                if (($oparg eq 'join' || $oparg eq 'order' || $oparg eq 'bond' )
                     && $sub !~ m{(?:join|order|bond)}) {
                    my @splitlocs = split(q(,), $sub);
                    #$loc_obj = Bio::Location::Split->new(-verbose => 1,
                    #                                     -splittype => $oparg);
                    while (my $splitloc = shift @splitlocs) {
                        #next unless $splitloc;
                        #my $sobj;
                        if ($splitloc =~ m{\(($LOCREG)\)}) {
                            my $comploc = $1;
                            $self->_parse_location($comploc);
                            #$sobj = $self->_parse_location($comploc);
                            #$sobj->strand(-1);
                        } else {
                            $self->_parse_location($splitloc);
                            #$sobj = $self->_parse_location($splitloc);
                        }
                        #$loc_obj->add_sub_Location($sobj);
                    }
                } else {
                    $loc_obj = $self->from_string($sub, $oparg);
                    # reinsure the operator is set correctly for this level
                    # unless it is complement
                    $loc_obj->splittype($oparg) unless $oparg eq 'complement';
                }
            }
            # no operator, simple or fuzzy 
            else {
                $loc_obj = $self->from_string($subloc,1);
            }
            #$loc_obj->strand(-1) if ($op && $op eq 'complement');
            #push @loc_objs, $loc_obj;
        }
        my $ct = @loc_objs;
        if ($op && !($op eq 'join' || $op eq 'order' || $op eq 'bond')
                && $ct > 1 ) {
            $self->throw("Bad operator $op: had multiple locations ".
                         scalar(@loc_objs).", should be SplitLocationI");
        }
        if ($ct > 1) {
            #$loc = Bio::Location::Split->new();
            #$loc->add_sub_Location(shift @loc_objs) while (@loc_objs);
            return $loc;
        } else {
            $loc = shift @loc_objs;
            return $loc;
        }
    } else { # simple location(s)
        $self->_parse_location($locstr);
        #$loc = $self->_parse_location($locstr);
        #$loc->strand(-1) if ($op && $op eq 'complement');
    }
    return $loc;
}

sub _parse_location {
    my ($self, $locstr) = @_;
    my ($loc, $seqid);
    $self->debug( "Location parse, processing $locstr\n");
    # 'remote' location?
    if($locstr =~ m{^(\S+):(.*)$}o) {
        # yes; memorize remote ID and strip from location string
        $seqid = $1;
        $locstr = $2;
    }
    
    # split into start and end
    my ($start, $end) = split(/\.\./, $locstr);
    # remove enclosing parentheses if any; note that because of parentheses
    # possibly surrounding the entire location the parentheses around start
    # and/or may be asymmetrical
    # Note: these are from X.Y fuzzy locations, which are deprecated!
    $start =~ s/(?:^\[+|\]+$)//g if $start;
    $end   =~ s/(?:^\[+|\]+$)//g if $end;

    # Is this a simple (exact) or a fuzzy location? Simples have exact start
    # and end, or is between two adjacent bases. Everything else is fuzzy.
    my $loctype = ".."; # exact with start and end as default

    $loctype = '?' if ( ($locstr =~ /\?/) && ($locstr !~ /\?\d+/) );

    my $locclass = "Biome::Location::Simple";
    if(! defined($end)) {
        if($locstr =~ /(\d+)([\.\^])(\d+)/) {
            $start = $1;
            $end = $3;
            $loctype = $2;
            $locclass = "Bio::Location::Fuzzy"
              unless (abs($end-$start) <= 1) && ($loctype eq "^");
        } else {
            $end = $start;
        }
    }
    # start_num and end_num are for the numeric only versions of 
    # start and end so they can be compared
    # in a few lines
    my ($start_num, $end_num) = ($start,$end);
    if ( ($start =~ /[\>\<\?\.\^]/) || ($end   =~ /[\>\<\?\.\^]/) ) {
        $locclass = 'Bio::Location::Fuzzy';
        if($start =~ /(\d+)/) {
            ($start_num) = $1;
        } else { 
            $start_num = 0
        }
        if ($end =~ /(\d+)/) {
            ($end_num)   = $1;
        } else { $end_num = 0 }
    } 
    my $strand = 1;

    if( $start_num > $end_num && $loctype ne '?') {
        ($start,$end,$strand) = ($end,$start,-1);
    }
    # instantiate location and initialize
    #$loc = $locclass->new(-verbose => $self->verbose,
    #                             -start   => $start, 
    #                             -end     => $end, 
    #                             -strand  => $strand, 
    #                             -location_type => $loctype);
    # set remote ID if remote location
    #if($seqid) {
    #    $loc->is_remote(1);
    #    $loc->seq_id($seqid);
    #}

    # done (hopefully)
    #return $loc;
}

no Biome;

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 NAME

Biome::Factory::FTLocationFactory - A FeatureTable Location Parser

=head1 VERSION

This documentation refers to Biome::Factory::FTLocationFactory version 0.01.

=head1 SYNOPSIS

  use Biome::Factory::FTLocationFactory;
  # parse a string into a location object
  $loc = Biome::Factory::FTLocationFactory->from_string("join(100..200,400..500");

=head1 DESCRIPTION

<TODO>
A full description of the module and its features.
May include numerous subsections (i.e., =head2, =head3, etc.).

=head1 SUBROUTINES/METHODS

=head2 from_string

 Title   : from_string
 Usage   : $loc = $locfactory->from_string("100..200");
 Function: Parses the given string and returns a Bio::LocationI implementing
           object representing the location encoded by the string.

           This implementation parses the Genbank feature table
           encoding of locations.
 Example :
 Returns : A Bio::LocationI implementing object.
 Args    : A string.

=head2 _parse_location

 Title   : _parse_location
 Usage   : $loc = $locfactory->_parse_location( $loc_string)

 Function: Parses the given location string and returns a location object 
           with start() and end() and strand() set appropriately.
           Note that this method is private.
 Returns : A Bio::LocationI implementing object or undef on failure
 Args    : location string

=head1 DIAGNOSTICS

<TODO>
A list of every error and warning message that the module can generate
(even the ones that will "never happen"), with a full explanation of each
problem, one or more likely causes, and any suggested remedies.

=head1 CONFIGURATION AND ENVIRONMENT

<TODO>
A full explanation of any configuration system(s) used by the module,
including the names and locations of any configuration files, and the
meaning of any environment variables or properties that can be set. These
descriptions must also include details of any configuration language used.

=head1 DEPENDENCIES

<TODO>
A list of all the other modules that this module relies upon, including any
restrictions on versions, and an indication of whether these required modules are
part of the standard Perl distribution, part of the module's distribution,
or must be installed separately.

=head1 INCOMPATIBILITIES

<TODO>
A list of any modules that this module cannot be used in conjunction with.
This may be due to name conflicts in the interface, or competition for
system or program resources, or due to internal limitations of Perl
(for example, many modules that use source code filters are mutually
incompatible).

=head1 BUGS AND LIMITATIONS

There are no known bugs in this module.

User feedback is an integral part of the evolution of this and other Biome and
BioPerl modules. Send your comments and suggestions preferably to one of the
BioPerl mailing lists. Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

Patches are always welcome.

=head2 Support 
 
Please direct usage questions or support issues to the mailing list:
  
L<bioperl-l@bioperl.org>
  
rather than to the module maintainer directly. Many experienced and reponsive
experts will be able look at the problem and quickly address it. Please include
a thorough description of the problem with code and data examples if at all
possible.

=head2 Reporting Bugs

Preferrably, Biome bug reports should be reported to the GitHub Issues bug
tracking system:

  http://github.com/cjfields/biome/issues

Bugs can also be reported using the BioPerl bug tracking system, submitted via
the web:

  http://bugzilla.open-bio.org/

=head1 EXAMPLES

<TODO>
Many people learn better by example than by explanation, and most learn better
by a combination of the two. Providing a /demo directory stocked with
well-commented examples is an excellent idea, but your users might not have
access to the original distribution, and the demos are unlikely to have been
installed for them. Adding a few illustrative examples in the documentation
itself can greatly increase the "learnability" of your code.

=head1 FREQUENTLY ASKED QUESTIONS

<TODO>
Incorporating a list of correct answers to common questions may seem like extra
work (especially when it comes to maintaining that list), but in many cases it
actually saves time. Frequently asked questions are frequently emailed
questions, and you already have too much email to deal with. If you find
yourself repeatedly answering the same question by email, in a newsgroup, on a
web site, or in person, answer that question in your documentation as well. Not
only is this likely to reduce the number of queries on that topic you
subsequently receive, it also means that anyone who does ask you directly can
simply be directed to read the fine manual.

=head1 COMMON USAGE MISTAKES

<TODO>
This section is really "Frequently Unasked Questions". With just about any kind
of software, people inevitably misunderstand the same concepts and misuse the
same components. By drawing attention to these common errors, explaining the
misconceptions involved, and pointing out the correct alternatives, you can once
again pre-empt a large amount of unproductive correspondence. Perl itself
provides documentation of this kind, in the form of the perltrap manpage.

=head1 SEE ALSO

<TODO>
Often there will be other modules and applications that are possible
alternatives to using your software. Or other documentation that would be of use
to the users of your software. Or a journal article or book that explains the
ideas on which the software is based. Listing those in a "See Also" section
allows people to understand your software better and to find the best solution
for their problem themselves, without asking you directly.

By now you have no doubt detected the ulterior motive for providing more
extensive user manuals and written advice. User documentation is all about not
having to actually talk to users.

=head1 (DISCLAIMER OF) WARRANTY

<TODO>
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=head1 ACKNOWLEDGEMENTS

<TODO>
Acknowledging any help you received in developing and improving your software is
plain good manners. But expressing your appreciation isn't only courteous; it's
also enlightened self-interest. Inevitably people will send you bug reports for
your software. But what you'd much prefer them to send you are bug reports
accompanied by working bug fixes. Publicly thanking those who have already done
that in the past is a great way to remind people that patches are always
welcome.

=head1 AUTHOR

Chris Fields  (cjfields at bioperl dot org)

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2009 Chris Fields (cjfields at bioperl dot org). All rights reserved.

followed by whatever licence you wish to release it under.
For Perl code that is often just:

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DESCRIPTION

Implementation of string-encoded location parsing for the Genbank feature
table encoding of locations.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to
the Bioperl mailing list.  Your participation is much appreciated.

  bioperl-l@bioperl.org                  - General discussion
  http://bioperl.org/wiki/Mailing_lists  - About the mailing lists

=head2 Support 

Please direct usage questions or support issues to the mailing list:

I<bioperl-l@bioperl.org>

rather than to the module maintainer directly. Many experienced and 
reponsive experts will be able look at the problem and quickly 
address it. Please include a thorough description of the problem 
with code and data examples if at all possible.

=head2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
of the bugs and their resolution. Bug reports can be submitted via the
web:

  http://bugzilla.open-bio.org/

=head1 AUTHOR - Hilmar Lapp

Email hlapp at gmx.net

=head1 CONTRIBUTORS

Jason Stajich, jason-at-bioperl-dot-org
Chris Fields, cjfields-at-uiuc-dot-edu

=head1 APPENDIX

The rest of the documentation details each of the object methods.
Internal methods are usually preceded with a _

