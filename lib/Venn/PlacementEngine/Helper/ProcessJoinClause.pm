package Venn::PlacementEngine::Helper::ProcessJoinClause;

=head1 NAME

Venn::PlacementEngine::Helper::ProcessJoinClause

=head1 DESCRIPTION

Process the join clause from the AssignmentGroup Type definition.

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

use Scalar::Util qw(reftype);
use Storable 'dclone';

no if $] >= 5.018, warnings => q{experimental::smartmatch};

=head1 METHODS

=head2 process_join_clause($join_clause, $table_alias)

Process the join clause from the assignmentgroup_type definition
( adding common elements )

    param ?join_clause : (HashRef/ArrayRef/Scalar) Join Clause
    param $table_alias : (Str) Table alias ("me" in DBIC-speak)
    return             : (HashRef) providertype_provider => [ all join clauses ]

=cut


sub process_join_clause {
    my ($self, $join_clause, $table_alias) = @_;

    my $ne_attributes = dclone($self->definition->{join_clause_non_explicit_attributes} || []);

    return $self->_processjc(dclone $join_clause, $table_alias, $ne_attributes );
}

=head2 _processjc($join_clause, $table_alias)

Internal recursive call for processing the join clause.

    param $entry       : (HashRef/ArrayRef/Scalar) Join Clause
    param $table_alias : (Str) Table alias ("me" in DBIC-speak)
    return             : (HashRef) providertype_provider => [ all join clauses ]

=cut

sub _processjc {
    my ($self, $entry, $table_alias, $attrs) = @_;

    my $type = reftype($entry) // "SCALAR";
    given ($type) {
        when (/^HASH$/) {
            for my $key (keys %$entry) {
                $entry->{$key} = $self->_processjc($entry->{$key}, $table_alias, $attrs);
            }
        }
        when (/^ARRAY$/) {
            my @tmp = map { $self->_processjc($_, $table_alias, $attrs) } @$entry;
            $entry = \@tmp;
        }
        when (/^SCALAR$/) {
            if ($entry eq $table_alias) {
                return {
                    "${entry}_provider" => $self->_gen_jc_joins($entry, $attrs),
                };
            }
            else {
                return {
                    $entry => {
                        "${entry}_provider" => $self->_gen_jc_joins($entry, $attrs),
                    }
                };
            }
        }
    }
    return $entry;
}

sub _gen_jc_joins {
    my ($self, $providertype, $attrs) = @_;
    $attrs //= [];

    # attrs = [qw( environments owner_eonids )]
    my @joins = map { "${providertype}_provider_" . $_ } @$attrs;
    return \@joins;
}


1;
