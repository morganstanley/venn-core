package Venn::PlacementEngine::Helper::JoinCorrelateFilter;

=head1 NAME

Venn::PlacementEngine::Helper::JoinCorrelateFilter

=head1 DESCRIPTION

Performs the [sql] joins, [assignment] correlations, and [resource placement] filters

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

requires qw( definition schema );

Venn::PlacementEngine::Strategy->helpers(qw[
    AttributePlacementCondition
    AddCorrelatedColumn
    ProcessJoinClause
]);

use Data::Dumper;

=head1 METHODS

=head2 join_correlate_filter()

Steps:
    Get base RS
    Generate base placement
    For each resource
      Get its provider_id and primary_field
      Build location base and resource-specific hash
      Attribute hashes
      Correlated subqueries to get _total, _avg_, _unassigned
    Generate filter where clause for capacity check
    Call search_rs/as_subselect_rs/etc. on base rs

    param \%placement : (HashRef) placement request hash
    return            : (ResultSet) resultset of placement options, joined, correlated, and filtered

=cut

## no critic (ProhibitExcessComplexity)
sub join_correlate_filter {
    my ($self, $opts) = @_;
    $opts //= {};

    # Base provider class resultset
    my $rs = $self->schema->resultset( $self->definition->{provider_class} );

    my (%base_placement, %attribute_placement, %manual_placement);

    my %location_placement = %{ $self->location_hash };

    my (@select, @as, %columns);

    #
    # Per-Resource Placement
    #   For each resource name (with its relationship path of e.g. cluster => rack)
    #   build up the inner queries including total, average, capacity for each resource
    #

    for my $resname ( keys %{ $self->definition->{providers} } ) {
        my $relationship_path = $self->definition->{providers}->{$resname};

        my ($resource_rs, $me, $primary_field);

        #
        # Determine if this is the base resource
        #   The definition defines a base resource to work from when specifying its related resources.
        #

        if ( $resname eq $self->definition->{me} ) {
            # if this is the base (starting) resource, we have to reference it differently

            ($resource_rs, $me) = ($rs, 'me');
            $primary_field = $rs->result_class->primary_field();

            # select resource's provider_id
            push @select, {
                ''  => [ 'me.provider_id' ],
                -as => $self->definition->{me}.'_provider_id'
            };
            push @as,  $self->definition->{me}.'_provider_id';

            # this is to also add in e.g. "cluster_name"
            push @select, "me.${primary_field}";
            push @as,     $primary_field;
        }
        else {
            ($resource_rs, $me) = ($rs->related_resultset_chain(@$relationship_path, $resname), $resname);
            $primary_field = $resource_rs->result_class->primary_field();

            # select resource's provider_id
            push @select, {
                ''  => [ "${resname}.provider_id"],
                -as =>   "${resname}_provider_id"
            };
            push @as,    "${resname}_provider_id";

            push @select, {
                ''  => [ "${resname}.${primary_field}" ],
                -as =>   "${resname}_${primary_field}" };
            push @as,    "${resname}_${primary_field}";

        }

        #
        # Basic conditions for placement
        #   Available_date, active state, etc.
        #

        if (defined $self->request->_raw_request->{as_of_date}) { ## no critic Subroutines::ProtectPrivateSubs
            $base_placement{"${resname}_provider.available_date"} = {
                '<=' => $self->request->_raw_request->{as_of_date}, ## no critic Subroutines::ProtectPrivateSubs
            };
        } else {
            $base_placement{"${resname}_provider.available_date"} = { '<=' => time() };
        }
        $base_placement{"${resname}_provider.state_name"}     = 'active';


        #
        # Manual Placement
        #   manual_placement field (per resource) to force placement onto the specified resource
        #

        if ( defined $self->request->manual_placement->{$resname} ) {
            $manual_placement{"${me}.${primary_field}"} = $self->request->manual_placement->{$resname};
        }

        # call each attribute's ResultSet jcf_placement() sub if it exists
        # add its placement result to %attribute_placement
        for my $attr_name (keys %{ Venn::Schema->attribute_mapping }) {
            my $attr_placement = $self->attribute_placement_condition($attr_name, $resname, $me);
            %attribute_placement = (%attribute_placement, %$attr_placement) if $attr_placement;
        }

        #
        # Correlated subqueries
        #   Used to determine assignment info for each resource
        #

        # Create a fresh resource resultset by calling new on the class name (so we don't pollute the subqueries)
        my $fresh_resource_rs = (ref $resource_rs)->new($resource_rs->result_source);

        # test columns are only used for validating results in tests, but are left out of prod queries
        if ( $opts->{test_columns} && ! $fresh_resource_rs->result_class->named_resources ) {
            # Assignment Total
            $self->add_correlated_column(\%columns, "${resname}_total",
                'assignment_total', $fresh_resource_rs, $me);

            # Assignment Group Count
            $self->add_correlated_column(\%columns, "${resname}_assignment_group_count",
                'assignment_group_count', $fresh_resource_rs, $me);
        }

        # Named Resources
        #   Resources that aren't "countable" like hostnames
        if ( ! $fresh_resource_rs->result_class->named_resources ) {
            # Unassigned
            $self->add_correlated_column(\%columns, "${resname}_unassigned",
                'unassigned', $fresh_resource_rs, $me);
        }
        else {
            # TODO: subquery to get _unassigned column for named resources
            $self->add_correlated_column(\%columns, "${resname}_unassigned",
                'unassigned_named', $fresh_resource_rs, $me);
        }
    }

    #
    # Filter providers that do not have enough capacity
    #

    my %rescount_where;
    # skip the capacity check if the force_placement option is set
    unless ($self->request->{force_placement}) {
        for my $resource (keys %{$self->request->resources}) {
            my $count = $self->request->resources->{$resource};
            $rescount_where{"me.${resource}_unassigned"} = { '>=' => \$count };
        }
    }

    #
    # Merge placements
    #   Merge the hashes containing the base, location, attribute, and manual placements
    #

    my %inner_placement = (%base_placement, %location_placement, %attribute_placement, %manual_placement);

    #
    # Process the join clause using the ProcessJoinClause helper
    #

    my $join_clause = $self->process_join_clause($self->definition->{join_clause}, $self->definition->{me});

    return $rs
        ->search_rs(\%inner_placement, {
            select     => \@select,
            as         => \@as,
            '+columns' => \%columns,
            join       => [
                # processed join_clause from the definition
                $join_clause,
                # join to anything needed for the location conditions to work
                $self->definition->{location_join},
                # anything needed for manual joins
                $self->definition->{join_clause_unprocessed},
            ],
        })
        # wrap the inner query with total/avg/assigned to filter
        # out placement options without enough capacity
        ->as_subselect_rs
        ->search_rs(\%rescount_where, {
            select    => \@as,
            as        => \@as,
            '+select' => [ keys %columns ],
            '+as'     => [ keys %columns ],
        });
}

1;
