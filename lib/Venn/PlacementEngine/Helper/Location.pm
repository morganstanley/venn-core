package Venn::PlacementEngine::Helper::Location;

=head1 NAME

Venn::PlacementEngine::Helper::Location

=head1 DESCRIPTION

Sets up the location hash.

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
use Storable 'dclone';

requires qw( log definition schema );
with qw( Venn::Role::Util );

=head1 METHODS

=head2 $self->location_hash()

    return : (HashRef) Location hash to use in a query condition

=cut

sub location_hash {
    my ($self) = @_;

    my %location;

    my %location_definition = %{ $self->definition->{location} };
    my %location_request    = %{ $self->request->location };

    for my $location (keys %location_definition) {
        my $location_path = $location_definition{$location};
        next unless defined $location_request{$location};

        # e.g. esxram.cluster.rack.building = 'hz'
        my $left_side = sprintf "%s.%s", join('.', @$location_path), $location;

        # check for arrayref right size => generate elements with OR clause
        if ((ref($location_request{$location}) // '') eq 'ARRAY') {
            $location{'-or'} = [];

            for (@{$location_request{$location}}) {
                push $location{'-or'}, { $left_side => $_ };
            }
        } elsif ((ref($location_request{$location}) // '') eq 'HASH') {
            my $condition = dclone($location_request{$location});

            $self->hash_replace($condition, $location, $left_side);
            %location = %{$self->hash_merge(\%location, $condition)};
        } else {
            $location{$left_side} = $location_request{$location};
        }
    }

    return \%location;
}

1;
