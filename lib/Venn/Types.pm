package Venn::Types;

=head1 NAME

Venn::Types

=head1 DESCRIPTION

Venn Type Library

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
use warnings;

use MooseX::Types -declare => [qw(
    DBIxException
    VennException
    NonNegativeNum
    NotEmptyStr
    PlacementResultState
)];

use MooseX::Types::Moose qw( Num Object Str );
use Moose::Util::TypeConstraints;

subtype DBIxException,
    as Object,
    where { $_->isa('DBIx::Class::Exception') },
    message { "Object is not of type DBIx::Class::Exception" };

subtype VennException,
    as Object,
    where { $_->isa('Venn::Exception') },
    message { "Object is not of type Venn::Exception" };

subtype NonNegativeNum,
    as Num,
    where { $_ >= 0 },
    message { "Value is not a non-negative number" };

subtype NotEmptyStr,
    as Str,
    where { length $_ > 0 },
    message { "String is empty" };

enum PlacementResultState,
    [qw( Pending Placed NotPlaced NoCapacity )];

1;
