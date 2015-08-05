package Venn::PlacementEngine::StrategyInterface;

=head1 NAME

Venn::PlacementEngine::StrategyInterface

=head1 DESCRIPTION

Interface for all Placement Engine Strategies. This enforces that
all concrete strategies define a name and a placement subroutine.

=head1 SYNOPSIS

    package Venn::PlacementEngine::Strategy::MyStrategy;

    use v5.14;

    use Moose;
    use MooseX::ClassAttribute;
    extends 'Venn::PlacementEngine::Strategy';
    with 'Venn::PlacementEngine::StrategyInterface';
    use namespace::autoclean;

    use Scalar::Util qw(reftype);

    Venn::PlacementEngine::Strategy->helpers(qw(
        MyStratHelper
        MyStratJoiner
    ));

    sub name { return "my_strat"; }

    augment 'place' => sub {
        my ($self) = @_;

        return $somekindofresultset;
    };

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

use Moose::Role;

requires 'name';

requires 'place';

1;
