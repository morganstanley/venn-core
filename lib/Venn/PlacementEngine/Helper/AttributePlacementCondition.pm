package Venn::PlacementEngine::Helper::AttributePlacementCondition;

=head1 NAME

Venn::PlacementEngine::Helper::AttributePlacementCondition

=head1 DESCRIPTION

Sets up the attribute placement condition.

=head1 AUTHOR

Venn Engineering

Josh Arenberg, Norbert Csongradi, Ryan Kupfer, Hai-Long Nguyen

=head1 LICENSE

Copyright 2013,2014,2015 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

use v5.14;
use Moose::Role;

requires qw( log schema );

=head1 METHODS

=head2 $self->attribute_placement_condition($attr_name, $resname)

Returns a JCF placement for this attribute as a HashRef.

    param $attr_name : (Str) Attribute name
    param $resname   : (Str) Resource name
    return           : (Maybe[HashRef]) Placement condition for the attribute

=cut

sub attribute_placement_condition {
    my ($self, $attr_name, $resname, $me) = @_;

    my $source = Venn::Schema->attribute_mapping->{$attr_name}->{source};
    return unless $source;

    my $rs = $self->schema->resultset($source);
    if (blessed $rs && $rs->can('jcf_placement')) {
        my $result = $rs->jcf_placement($self, $resname, $me);
        return unless defined $result;
        if (ref $result && ref $result eq 'HASH') {
            return $result;
        }
        else {
            $self->log->warnf("Attribute %s returned an invalid result for jcf_placement: %s",
                $attr_name, Dumper $result);
        }
    }
    return;
}

1;
