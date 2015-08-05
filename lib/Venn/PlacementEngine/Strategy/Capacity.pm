package Venn::PlacementEngine::Strategy::Capacity;

=head1 NAME

Venn::PlacementEngine::Strategy::Capacity;

=head1 DESCRIPTION

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
extends 'Venn::PlacementEngine::Strategy';
with qw(
    Venn::Role::Logging
    Venn::PlacementEngine::StrategyInterface
);
use namespace::autoclean;

use Data::Dumper;

Venn::PlacementEngine::Strategy->helpers(qw[
    AttributePlacementCondition
    Location
    ProcessJoinClause
]);

## no critic (ProtectPrivateSubs)

=head1 METHODS

=head2 name()

Name of the strategy

    return : (Str) Strategy name

=cut

sub name { return "capacity"; }

has 'subquery_count' => (
    is      => 'rw',
    isa     => 'Int',
    default => 0,
    documentation => 'Count of generated sub-queries required for aliasing',
);

augment 'place' => sub {
    my ($self) = @_;

    # TODO: Exception
    die "Unable to place using the Capacity Strategy.";
};

=head1 METHODS

=head2 capacity()

Returns total AGT capacity count for given placement options

    return           : (Int) AGT capacity count

=cut

sub capacity {
    my ($self) = @_;
    my %summary;

    $self->log->debugf("Capacity placement request: %s", Dumper $self->request->_raw_request);

    my @containers;
    foreach my $resname (keys %{ $self->definition->{providers} }) {
        # Omit if not specified in the placement
        next if not defined $self->request->resources->{$resname};

        # Get container field aliases
        my $me = $self->definition->{me} ? 'me' : $resname;
        my $container_fields = $self->_clauses_for_res($resname, $me)->{as};

        # Add container field aliases to SELECT/AS/GROUP BY clauses
        my @select = ( { sum => 'agtcount', -as => 'agtsum' } );
        my @as = ( 'agtsum' );
        my @group_by;
        foreach my $field (@$container_fields) {
            push @select,   $field;
            push @as,       $field;
            push @group_by, $field;
        }

        # Query object for resource's provider capacity
        my $query = $self->_resource_capacity($resname)
            ->as_subselect_rs
            ->search_rs(undef, {
                select      => \@select,
                as          => \@as,
                group_by    => \@group_by,
            })
            ->as_query;

        # Retrieve and store capacity for individual resource
        my $res_cap = $self->_resource_capacity($resname)
            ->as_subselect_rs
            ->search_rs(undef, {
                select => [
                    {
                        coalesce => [
                            { sum => 'agtcount' },
                            0
                        ],
                        -as => 'agtsum',
                    },
                ],
                as => [ 'agtsum' ],
            });
        $summary{$resname} = 0 + $res_cap->first->get_column('agtsum');

        # Add query object to traversal structure
        $self->_add_to_traversal(\@containers, $container_fields, $query);
    }

    # Generate query from the root
    my @bindings;
    my $root_field = (keys %{$containers[0]})[0];
    $self->subquery_count(0);
    my $final_query = $self->_container_capacity(
        $containers[0]->{$root_field},
        [ $root_field ],
        \@bindings,
    );

    # Perform search
    my $capacity = $self->schema->storage->dbh->selectrow_arrayref(
        $final_query,
        { Slice => {} },
        (@bindings),
    );

    $summary{capacity} = 0 + ($capacity->[0] || 0);

    return \%summary;
}

=head2 $self->_resource_capacity($resname)

Search for AGT capacity for all providers for given resource $resname,
grouped by the resource's parent containers.

Example of result set:
    [
        {
            'cluster_name'  => 'zyec11',
            'rack_name'     => 'zy1',
            'agt_count'     => 435
        },
        {
            'cluster_name'  => 'zyec12',
            'rack_name'     => 'zy1',
            'agt_count'     => 326
        },
    ]

param $resname  : (Str) Resource name from AGT definition
return          : (ResultSet)

=cut

sub _resource_capacity {
    my ($self, $resname) = @_;
    my (%columns);

    # Base provider class
    my ($resource_rs, $me);
    my $rs = $self->schema->resultset($self->definition->{provider_class});
    my $relationship_path = $self->definition->{providers}->{$resname};

    if ($resname eq $self->definition->{me}) {
        $resource_rs = $rs;
        $me         = 'me';
    }
    else {
        $resource_rs = $rs->related_resultset_chain(@$relationship_path, $resname);
        $me          = $resname;
    }

    # Base placement
    my %base_placement;

    if (defined $self->request->_raw_request->{provider_as_of_date}) {
        $base_placement{"${resname}_provider.available_date"} = {
            '<=' => $self->request->_raw_request->{provider_as_of_date},
        };
    }
    $base_placement{"${resname}_provider.state_name"} = $self->request->_raw_request->{provider_state} || 'active';

    # Unassigned resources
    my $size = $self->request->resources->{$resname};

    my $fresh_resource_rs = (ref $resource_rs)->new($resource_rs->result_source);

    if ( ! $fresh_resource_rs->result_class->named_resources ) {
        $columns{"agtcount"} = {
            coalesce => [
                $fresh_resource_rs->get_correlated_agt_capacity(
                    "${me}.provider_id", $self->request->assignmentgroup_type, $size,
                    $self->request->_raw_request->{as_of_date},
                )->as_query,
                0
            ],
            -as => "agtcount",
        };
    }
    else {
        $columns{"agtcount"} = {
            coalesce => [
                $fresh_resource_rs->get_correlated_agt_capacity_nr(
                    "${me}.provider_id", $size, $self->request->_raw_request->{as_of_date},
                )->as_query,
                0
            ],
            -as => "agtcount",
        };
    }

    # Location placement
    my %location_placement = %{ $self->location_hash };

    # call each attribute's ResultSet jcf_placement() sub if it exists
    # add its placement result to %attribute_placement
    my %attribute_placement;
    for my $attr_name (keys %{ Venn::Schema->attribute_mapping }) {
        my $attr_placement = $self->attribute_placement_condition($attr_name, $resname, $me);
        %attribute_placement = (%attribute_placement, %$attr_placement) if $attr_placement;
    }

    # Manual placement
    my %manual_placement;
    if ( defined $self->request->manual_placement->{$resname} ) {
        my $primary_field = $resource_rs->result_class->primary_field;
        $manual_placement{"${me}.$primary_field"} = $self->request->manual_placement->{$resname};
    }

    # Gather all placement options
    my %inner_placement = (%base_placement, %location_placement, %attribute_placement, %manual_placement);

    # SELECT, AS, GROUP BY clauses
    my $clauses = $self->_clauses_for_res($resname, $me);

    # Join clause
    my $join_clause = $self->process_join_clause( $self->definition->{join_clause}, $self->definition->{me} );

    return $rs
        ->search_rs(\%inner_placement, {
            select     => $clauses->{select},
            as         => $clauses->{as},
            '+columns' => \%columns,
            join       => [
                $join_clause, $self->definition->{location_join}, $self->definition->{join_clause_unprocessed},
            ],
            group_by   => $clauses->{group_by},
        });
}

=head2 _clauses_for_res($resname, $me)

Retrieve SELECT, AS and GROUP BY clauses to be used for resource capacity.

    param $resname          : (Str) Resource name
    param $me               : (Str) Whether this is the base provider class
    return                  : (HashRef) SELECT, AS and GROUP BY clauses

=cut

sub _clauses_for_res {
    my ($self, $resname, $me) = @_;

    # Clauses to return
    my (@select, @as);
    my @group_by = ( "${me}.provider_id" );

    # Immediate parent Container of Provider
    my $provider_rs = $self->schema->resultset($self->schema->provider_mapping->{$resname}->{source});
    my $immediate_container_field = $provider_rs->result_class->container_field();

    push @select, {
        ''  => "${me}.${immediate_container_field}",
        -as => "${immediate_container_field}",
    };
    push @as,       "${immediate_container_field}";
    push @group_by, "${me}.${immediate_container_field}";

    # Current Container in the AGT hierarchy
    my $current_container_rs = $self->schema->resultset($provider_rs->result_class->container_class);

    # Determine if we are already at the root Container (i.e. 2-level hierarchy)
    my $at_root_container = defined $current_container_rs->result_class->container_name ? 0 : 1;

    while (not $at_root_container) {
        my $container_name  = $current_container_rs->result_class->container_name;
        my $container_field = $current_container_rs->result_class->container_field;

        push @select, {
            ''  => "${container_name}.${container_field}",
            -as => "${container_field}",
        };
        push @as,       "${container_field}";
        push @group_by, "${container_name}.${container_field}";

        # Parent Container in the AGT Hierarchy
        my $parent_container_rs = $self->schema->resultset(
            $self->schema->container_mapping->{ $current_container_rs->result_class->container_name }->{source},
        );

        # Parent Container has a parent Container, move up in the AGT Hierarchy
        if (defined $parent_container_rs && defined $parent_container_rs->result_class->container_name) {
            $current_container_rs = $parent_container_rs;
        }
        # Otherwise, we're at the root Container, done
        else {
            $at_root_container = 1;
        }
    }

    return {
        select      => \@select,
        as          => \@as,
        group_by    => \@group_by,
    }
}

=head2 _add_to_traversal($containers, $container_fields, $query)

Add query object to the traversal structure based on it's position in the AGT
hierarchy, given it's container fields

    param $containers       : (ArrayRef) Traversal structure
    param $container_fields : (Str) Parent container fields of the resource's provider
    param $query_obj        : (Str) Capacity query object for the resource

=cut

sub _add_to_traversal {
    my ($self, $containers, $container_fields, $query) = @_;

    # Create traversal structure to resource capacity objects
    # zephyr example:
    #   $containers = [
    #       {
    #           rack_name => {
    #               cluster_name => [ esxram_cap_query_obj, esxcpu_cap_query_obj ],
    #               network_name => [ hostname_cap_query_obj ],
    #               filer_name => [ nas_cap_query_obj, filerio_cap_query_obj ]
    #           }
    #       }
    #   ]
    #
    # sanvcs example:
    #   $containers = [
    #       {
    #           rack_name => {
    #               cluster_name => [ esxram_cap_query_obj, esxcpu_cap_query_obj,
    #                   {
    #                       filesystem_name => [ fsdisk_cap_query_obj, fsdio_cap_query_obj ]
    #                   }
    #               ]
    #           }
    #       }
    #   ]
    my $i = 0;
    my $position = $containers;
    foreach my $field ( reverse @$container_fields ) {
        my $container_found = 0;
        $i++;

        foreach my $child (@$position) {
            if (ref $child eq 'HASH') {
                if (exists $child->{$field}) {
                    if ($i == @$container_fields) {
                        push @{$child->{$field}}, $query;
                    }
                    else {
                        $position = $child->{$field};
                    }

                    $container_found = 1;
                }
            }
            else {
                # Provider, don't care here.
            }
        }

        if (not $container_found) {
            if ($i == @$container_fields) {
                push @$position, {
                    $field => [ $query ],
                };
            }
            else {
                my $new_container = { $field => [] };
                push @$position, $new_container;

                $position = $new_container->{$field};
            }
        }
    }

    return;
}

=head2 $self->_container_capacity($container, $container_aliases, $bindings)

Generate SQL query for a Container, AKA the "caprollup". If a Container has
child Containers, this method will call itself to generate the SQL query for
that child Container.

    param $container            : (ArrayRef) Container's contents
    param $container_aliases    : (ArrayRef) Container field names up to the parent
    param $bindings             : (ArrayRef) SQL bindings to add as structure is traversed
    return                      : (Str) Generated SQL query

    Example of generated SQL, sanvcs:
      SELECT SUM(sub5.agtsum) as agtsum
      FROM (
        SELECT rack_name, SUM(limiting_count) as agtsum
        FROM (
          SELECT sub4.rack_name as rack_name, sub4.cluster_name as cluster_name, MIN(SUM(sub2.agtsum), SUM(sub3.agtsum), SUM(sub4.agtsum)) as limiting_count
          FROM (
            SELECT rack_name, cluster_name, SUM(limiting_count) as agtsum
            FROM (
              SELECT sub1.rack_name as rack_name, sub1.cluster_name as cluster_name, sub1.filesystem_name as filesystem_name, MIN(SUM(sub0.agtsum), SUM(sub1.agtsum)) as limiting_count
              FROM ($fsdisk_sql) as sub0, ($fsio_sql) as sub1
              WHERE sub1.filesystem_name = sub0.filesystem_name
              GROUP BY sub1.rack_name, sub1.cluster_name, sub1.filesystem_name
            )
            GROUP BY rack_name, cluster_name
          ) as sub2, ($esxram_sql) as sub3, ($esxcpu_sql) as sub4
          WHERE sub3.cluster_name = sub2.cluster_name AND sub4.cluster_name = sub3.cluster_name
          GROUP BY sub4.rack_name, sub4.cluster_name
        )
        GROUP BY rack_name
      ) as sub5

    Example of generated SQL, zlight:
      SELECT MIN(SUM(sub4.agtsum), SUM(sub5.agtsum)) as agtsum
      FROM
        (
          SELECT rack_name, SUM(limiting_count) as agtsum
          FROM (
            SELECT sub1.rack_name as rack_name, sub1.filer_name as filer_name, MIN(SUM(sub0.agtsum), SUM(sub1.agtsum)) as limiting_count
            FROM ($nas_sql) as sub0, ($filerio_sql) as sub1
            WHERE sub1.filer_name = sub0.filer_name
            GROUP BY sub1.rack_name, sub1.filer_name
          )
          GROUP BY rack_name
          ) as sub4,
          (
          SELECT rack_name, SUM(limiting_count) as agtsum
          FROM (
            SELECT sub3.rack_name as rack_name, sub3.cluster_name as cluster_name, MIN(SUM(sub2.agtsum), SUM(sub3.agtsum)) as limiting_count
            FROM ($esxram_sql) as sub2, ($esxcpu_sql) as sub3
            WHERE sub3.cluster_name = sub2.cluster_name
            GROUP BY sub3.rack_name, sub3.cluster_name
          )
          GROUP BY rack_name
        ) as sub5
      WHERE sub5.rack_name=sub4.rack_name

=cut

sub _container_capacity {
    my ($self, $container, $container_aliases, $bindings) = @_;

    my @queries;
    foreach my $child (@$container) {
        # Sub-Container structure
        if (ref $child eq 'HASH') {
            my @container_aliases = ( @$container_aliases, (keys %$child)[0] );

            # Generate SQL for this Sub-Container
            push @queries, $self->_container_capacity(
                (values %$child)[0],
                \@container_aliases,
                $bindings,
            );
        }
        # Sub-Provider query object
        else {
            my ($sql, @bind) = @$$child;
            push @$bindings, $self->_dbic_to_dbh_binds(\@bind);
            push @queries, $sql;
        }
    }

    # Generate SELECT, FROM, WHERE clauses
    my (@select, @from, @where);
    my $immediate_container_field = $container_aliases->[-1];
    for (my $child_count = 0; $child_count < @$container; $child_count++) {
        my $subquery_count = $self->subquery_count;
        my $prior_subquery_count = $subquery_count - 1;

        push @select, "SUM(sub${subquery_count}.agtsum)";
        push @from, "($queries[${child_count}]) as sub${subquery_count}";
        push @where,
            "sub${subquery_count}.${immediate_container_field}=sub${prior_subquery_count}.${immediate_container_field}"
            if $child_count >= 1;
        $self->subquery_count($subquery_count + 1);
    }

    my $select_str = join ',', @select;
    $select_str = "MIN(${select_str})" if @select >= 2;

    my $from_str = join ',', @from;

    my $where_str = @where ? 'WHERE ' . join(' AND ', @where) : '';

    my $query;
    my $inner_count = $self->subquery_count - 1;
    if (@$container_aliases > 1) {
        my (@outer_select_containers, @inner_select_containers, @inner_group_by_containers);

        for (my $c = 0; $c < @$container_aliases; $c++) {
            my $alias = $container_aliases->[$c];
            push @outer_select_containers, $alias if $c != @$container_aliases - 1;

            push @inner_select_containers,   "sub${inner_count}.${alias} as ${alias}";
            push @inner_group_by_containers, "sub${inner_count}.${alias}";
        }
        my $outer_select_containers_str   = join ',', @outer_select_containers;
        my $inner_select_containers_str   = join ',', @inner_select_containers;
        my $inner_group_by_containers_str = join ',', @inner_group_by_containers;

        $query = <<"EOT";
SELECT ${outer_select_containers_str}, SUM(limiting_count) as agtsum FROM(
SELECT ${inner_select_containers_str}, ${select_str} as limiting_count
FROM ${from_str}
${where_str}
GROUP BY ${inner_group_by_containers_str}
)
GROUP BY ${outer_select_containers_str}
EOT
    }
    else {
        $query = <<"EOT";
SELECT ${select_str} as agtsum
FROM ${from_str}
${where_str}
EOT
    }

    return $query;
}

=head2 $self->_dbic_to_dbh_binds($dbic_binds)

Convert dbic bindings so they may be used for dbh

    param $dbic_binds   : (ArrayRef) dbic bindings for query
    return              : (Array) Bindings converted for dbh

=cut

sub _dbic_to_dbh_binds {
    my ($self, $dbic_binds) = @_;

    return map { $_->[1] } @$dbic_binds;
}


=head1 AUTHOR

Venn Engineering

=cut

__PACKAGE__->meta->make_immutable;
