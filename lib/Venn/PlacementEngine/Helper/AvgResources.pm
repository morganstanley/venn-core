package Venn::PlacementEngine::Helper::AvgResources;

=head1 NAME

Venn::PlacementEngine::Helper::AvgResources

=head1 DESCRIPTION

Averages the AssignmentGroup size per provider type

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

requires 'log';
requires 'definition';
requires 'schema';

Venn::PlacementEngine::Strategy->helpers(qw/ Location /);

use Data::Dumper;

=head1 METHODS

=head2 avg_resources()

Returns a hashref containing the average assignmentgroup size per resource.
ex: (
    esxram_avg  => 10.3333333333,
    esxcpu_avg  => 2120,
    nas_avg     => 40,
    filerio_avg => 22.3333333333,
)

    return : (HashRef[Num]) List all of per-resource averages

=cut

sub avg_resources {
    my ($self) = @_;

    my %columns;

    for my $resource ( keys %{ $self->definition->{providers} } ) {
        my %args = (
            providertype => $resource,
        );

        my %location = %{ $self->location_hash };
        if (%location) {
            $args{location_hash} = \%location;
            push @{ $args{join} }, { $resource => $self->definition->{provider_to_location_join}->{$resource} };
        }

        $columns{"${resource}_avg"} = $self->schema->resultset('Provider')
            ->average_assigned( \%args, $resource, $self->request->attributes )
            ->as_query;
    }

    my $avg = $self->schema->resultset('Provider')
        ->search( undef, { columns => \%columns } )
        ->as_hash
        ->first;

    $self->log->debugf("Average resources found during placement: %s", Dumper($avg));

    return $avg;
}


1;
