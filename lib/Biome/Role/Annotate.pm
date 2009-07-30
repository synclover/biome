package Bio::Moose::Role::Annotate;

use Bio::Moose::Role;

requires qw(as_text);

has tag_name => (
    is          => 'rw',
    does        => 'Str'
);

has DEFAULT_CB => (
    is          => 'ro',
    isa         => 'CodeRef',
    required    => 1,
    );

sub hash_tree {
    my ($self) = @_;
    my $h = {};
    # do a little introspection using the meta class 
    for my $att ($self->meta->get_all_attributes) {
        next unless $att->has_value($self);
        $h->{$att->name} = $att->get_value($self);
    }
    $h;
}

sub display_text {
    my ($self, $cb) = @_;
    $cb ||= $self->DEFAULT_CB;
    $self->throw("Callback must be a code reference") if ref $cb ne 'CODE';
    return $cb->($self);
}

no Bio::Moose::Role;

1;

__END__

=head2 as_text

 Title   : as_text
 Usage   :
 Function: single text string, without newlines representing the
           annotation, mainly for human readability. It is not aimed
           at being able to store/represent the annotation.
 Example :
 Returns : a string
 Args    : none
 Status  : Stable

=cut

=head2 display_text

 Title   : display_text
 Usage   : my $str = $ann->display_text();
 Function: returns a string. Unlike as_text(), this method returns a string
           formatted as would be expected for the specific implementation.

           Implementations should allow passing a callback as an argument which
           allows custom text generation; the callback will be passed the
           current implementation.

           Note that this is meant to be used as a simple representation
           of the annotation data but probably shouldn't be used in cases
           where more complex comparisons are needed or where data is
           stored.
 Example :
 Returns : a string
 Args    : [optional] callback
 Status  : Stable

=cut

=head2 hash_tree

 Title   : hash_tree
 Usage   :
 Function: should return an anonymous hash with "XML-like" formatting
 Example :
 Returns : a hash reference
 Args    : none
 Status  : Uncertain

=cut

=head2 tagname

 Title   : tagname
 Usage   : $obj->tagname($newval)
 Function: Get/set the tagname for this annotation value.

           Setting this is optional. If set, it obviates the need to
           provide a tag to Bio::AnnotationCollectionI when adding
           this object. When obtaining an AnnotationI object from the
           collection, the collection will set the value to the tag
           under which it was stored unless the object has a tag
           stored already.

 Example :
 Returns : value of tagname (a scalar)
 Args    : new value (a scalar, optional)
 Status  : Stable

=cut