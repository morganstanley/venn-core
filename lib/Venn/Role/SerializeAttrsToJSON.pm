package Venn::Role::SerializeAttrsToJSON;

=head1 NAME

Venn::Role::SerializeAttrsToJSON

=head1 DESCRIPTION

Serializes to JSON

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

=head1 METHODS

=head2 TO_JSON()

Serializes this object to json.

    return : (HashRef) Serialized JSON hash of this object

=cut

use v5.14;
use Moose::Role;

use Scalar::Util qw( blessed );

sub TO_JSON {
    my ($self) = @_;

    my %json_hash;
    for my $attr ( $self->meta->get_all_attributes ) {
        next if $attr->does('Moose::Meta::Attribute::Custom::Trait::NoSerialize');

        my $name = $attr->name;
        if (blessed $self->$name && $self->$name->can('TO_JSON')) {
            $json_hash{$name} = $self->$name->TO_JSON();
        }
        else {
            $json_hash{$name} = $self->$name;
        }
    }
    return \%json_hash;
}


1;
