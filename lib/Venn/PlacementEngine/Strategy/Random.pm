package Venn::PlacementEngine::Strategy::Random;

=head1 NAME

Venn::PlacementEngine::Strategy::Random

=head1 DESCRIPTION

Randomly places

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
use Moose;
use MooseX::ClassAttribute;
extends 'Venn::PlacementEngine::Strategy';
with 'Venn::PlacementEngine::StrategyInterface';

use namespace::autoclean;

#Venn::PlacementEngine::Strategy->helpers(qw());

=head1 METHODS

=head2 name()

Name of the strategy

    return : (Str) Strategy name

=cut

sub name { return "random"; }

=head2 place()

Places using the Random placement strategy.

    return : (HashRef) Placement Location

=cut

sub place {
    my ($self) = @_;

    my $join_correlate_filter = $self->join_correlate_filter();
    my $placement_row = $join_correlate_filter->rand;

    $self->result->placement_rs($placement_row);
    $self->result->placement_location($placement_row->as_hash->single);

    return $self->result;
}

1;
