package Venn::PlacementEngine::Helper::AddCorrelatedColumn;

=head1 NAME

Venn::PlacementEngine::Helper::AddCorrelatedColumn

=head1 DESCRIPTION

Adds a correlated column to the passed in column hashref.

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

requires qw( log );

=head1 METHODS

=head2 $self->add_correlated_column(\%cols, $column_name, $correlated_sub, $rs, $me)

Adds a correlated column ($column_name) to the column hashref (\%cols) by calling
$rs->get_correlated_${correlated_sub}. Passes $me.provider_id to the correlated
subroutine and expects a ResultSet to be returned (so that it may call ->as_query on it).

    param \%columns        : (HashRef) hashref of columns
    param  $column_name    : (Str) name of the column to add
    param  $correlated_sub : (Str) name of the correlated sub (minus "get_correlated_")
    param  $rs             : (ResultSet) resultset on which to call the correlated sub
    param  $me             : (Str) the current table alias

=cut

sub add_correlated_column {
    my ($self, $columns, $column, $correlated_sub, $rs, $me) = @_;

    my $method = "get_correlated_${correlated_sub}";
    if (! $rs->can($method)) {
        die "Invalid corrected sub: $method\n"; # TODO: exception
    }

    $columns->{$column} = {
        coalesce => [
            $rs->$method("${me}.provider_id", $self->request->assignmentgroup_type)->as_query,
            0
        ],
        -as => $column,
    };
    return;
}

1;
