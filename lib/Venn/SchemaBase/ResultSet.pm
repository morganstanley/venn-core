package Venn::SchemaBase::ResultSet;

=head1 NAME

Venn::SchemaBase::ResultSet

=head1 DESCRIPTION

Base DBIC ResultSet

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
use MooseX::NonMoose;
use namespace::autoclean;
extends 'DBIx::Class::ResultSet';
with 'Venn::Role::Logging';

use DBIx::Class::ResultClass::HashRefInflator;
use Data::Dumper;

use Venn::Exception qw( API::InvalidSortPair );

__PACKAGE__->load_components(qw{
    Helper::ResultSet::SetOperations
    Helper::ResultSet::CorrelateRelationship
    Helper::ResultSet::Random
});

=head1 METHODS

=head2 BUILDARGS(...)

Fix for MooseX::NonMoose and DBIx::Class combo

    return : (array) Args for BUILD

=cut

sub BUILDARGS { $_[2] } ## no critic (RequireArgUnpacking,RequireFinalReturn)

=head2 as_hash()

Returns the result as a hash reference using HashRefInflator.

    return : (hashref) ResultSet as a HashRef

=cut

sub as_hash {
    my ($self) = @_;

    $self->result_class('DBIx::Class::ResultClass::HashRefInflator');
    return $self;
}

=head2 as_hash_round()

Same as as_hash, but converts any floats ( including those in scientific notation
ala DB2 ) to a rounded, two-decimal-place format.

    return : (hashref) ResultSet as a HashRef

=cut

sub as_hash_round {
    my ($self) = @_;

    $self->result_class('Venn::ResultClass::HashRefInflatorFloatConvert');
    return $self;
}

sub search_readonly {
    my ($self, $cond, $attrs) = @_;

    if ($self->result_source->schema->storage_type =~ /db2/i) {
        $attrs //= {};
        $attrs->{for} = \'READ ONLY WITH UR';
    }

    return $self->search($cond, $attrs);
}

=head2 related_resultset_chain(@relationships)

Returns the last related resultset using an array/path of relationships.

    return : (ResultSet) Last relationship ResultSet

=cut

sub related_resultset_chain {
    my ($self, @chain) = @_;

    my $rs = $self;
    for my $rel (@chain) {
        $rs = $rs->related_resultset($rel);
    }
    return $rs;
}

=head2 prefetch(\@tables)

Prefetches specified tables. This pulls in the other table and its values.

    param \@tables : (arrayref) list of tables

=cut

sub prefetch {
    my ($self, $tables) = @_;

    return $self->search(undef, { prefetch => $tables });
}

=head2 join_tables(\@tables)

joins specified tables. This pulls in the other table and its values.

    param \@tables : (arrayref) list of tables

=cut

sub join_tables {
    my ($self, $tables) = @_;

    return $self->search(undef, { join => $tables });
}

=head2 as_alias($alias_name)

Aliases the current ResultSet table to $alias_name.

    param $alias_name : (Str) Name of the alias
    return            : (ResultSet) Modified ResultSet

=cut

sub as_alias {
    my ($self, $alias_name) = @_;

    return $self->search(undef, { alias => $alias_name });
}

=item search_with_query_params

Parses query parameters to form the where clause and attributes
of the query.

    param  $c    : (object) Catalyst context
    param \%opts : (hashref) Options for parsing query params
    return       : (resultset) ResultSet with appropriate conds/attrs
    throws       : API::InvalidSortPair, ...

=cut

sub search_with_query_params {
    my ( $self, $c, $opts ) = @_;

    $opts->{attrs}{allowed} = [qw(
        order_by
        columns
        join
        prefetch
        page
        rows
        offset
        group_by
        having
        distinct
    )];

    my $me = $self->current_source_alias;

    # this will eventually go away when we can replace it with something more elegant,
    # so for now, please excuse the complexities
    ## no critic (ProhibitComplexMappings,ProhibitMutatingListFunctions)
    my %conditions = map {
        next unless $_ =~ /^filter_/;
        my $orig = $_;
        $_ =~ s/^filter_//;
        my $alias = sprintf("%s.%s", $me, $_);
        $c->req->params->{$orig} =~ /%/
            ? ( $alias => { -like => $c->req->params->{$orig} } )
            : ( $alias => $c->req->params->{$orig} )
    } grep { /filter_/ } keys %{$c->req->params};
    ## use critic

    my %attributes;
    for my $attr (@{$opts->{attrs}->{allowed}}) {
        next if exists $opts->{attrs}->{disallowed}->{$attr};
        $attributes{$attr} = $c->req->params->{$attr} if defined $c->req->params->{$attr};
    }

    # special cases: ordering
    if (exists $c->req->params->{sort} && exists $c->req->params->{dir}) {
        my $dir = lc $c->req->params->{dir};
        if ($dir eq 'asc' || $dir eq 'desc') {
            $attributes{order_by} = { "-$dir" => $c->req->params->{sort} };
        }
    }
    elsif (exists $c->req->params->{order_by}) {
        my @sort_pairs = split /,/, $c->req->params->{order_by};
        for my $pair (@sort_pairs) {
            my ($column, $direction) = ( $pair =~ /^(\S+) (asc|desc)$/i );
            $attributes{order_by} = [];
            if ($column && $direction) {
                push @{$attributes{order_by}}, { "-$direction" => $column };
            }
            else {
                Venn::Exception::API::InvalidSortPair->throw({ c => $c, pair => $pair });
            }
        }
    }

    #$c->log->debug("Conditions: " . Dumper(\%conditions));
    #$c->log->debug("Attributes: " . Dumper(\%attributes));

    return $self->search(\%conditions, \%attributes);
}

=head2 lock_table($mode)

Locks a table if using db2. If not db2, this is a no-op.
Defaults to the associated table for the resultset's resultsource
Defaults to EXCLUSIVE mode for the table lock.

=cut

sub lock_table {
    my ($self, $mode) = @_;
    $mode //= 'EXCLUSIVE';

    my $tablename = $self->result_source->name;

    my $schema = $self->result_source->schema;
    if ( $schema->storage_type =~ /db2/i ) {
        return $schema->storage->dbh_do(
            sub {
                my ($storage, $dbh) = @_;
                $dbh->do("LOCK TABLE $tablename IN $mode MODE");
            }
        );
    }
    return;
}

=head2 find_by_primary_field($primary_field)

Retrieve record by primary_field

    param $primary_field    : (Str) Value of field to search on
    return                  : (ResultSet)

=cut

sub find_by_primary_field {
    my ($self, $primary_field) = @_;

    return $self->single( { $self->result_class->primary_field => $primary_field } );
}

sub container_name {
    my ($self) = @_;

    return ref($self) =~ /::(?:[A-Z]_)?([^:]+)$/ ? $1 : '';
}

=head2 agt_definition([$agt_name])

Returns definition for AGT

    param $assignmentgroup_type : (string) AGT name (example: zlight),
                                  automatically set when $self->agt_name defined
    return                      : (hash) Definition for AGT

=cut

sub agt_definition {
    my ($self, $assignmentgroup_type) = @_;

    $assignmentgroup_type //= $self->agt_name // die "Can't find out agt_name";

    return $self->result_source->schema->resultset('AssignmentGroup_Type')
      ->single({ assignmentgroup_type_name => $assignmentgroup_type })
      ->definition;
}

1;
