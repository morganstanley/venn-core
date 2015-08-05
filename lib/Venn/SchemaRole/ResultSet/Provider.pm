package Venn::SchemaRole::ResultSet::Provider;

=head1 NAME

Venn::SchemaRole::ResultSet::Provider

=head1 DESCRIPTION

Role for all provider subclasses (P_*)

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

use Carp;
use Try::Tiny;
use Data::Dumper;
use Scalar::Util qw(looks_like_number);

=head1 METHODS

=head2 with_unassigned_resources($random)

Add unassigned resources to providers with named resources.

    param $random : (Bool) Return them in a random order
    return        : (ResultSet) ResultSet with unassigned resources

=cut

sub with_unassigned_resources {
    my ($self, $random) = @_;
    $random //= 1;
    die 'provider does not have named resources' unless $self->result_class->named_resources;
    my $resourcename = $self->result_class->named_resources_resourcename;
    my $rs = $self->search({
            'assignment.resource_id'    => undef,
            'resources.available_date'  => { '<=' => time() },
        },
        {
            '+select' => [ 'resources.resource_id', "resources.$resourcename" ],
            '+as'     => [ 'resource_id', $resourcename ],
            join      => { resources => 'assignment' },
        },
    );
    return $random ? $rs->rand : $rs;
}

=head2 with_provider()

Select the provider and extended table as one flat list.

=cut

sub with_provider {
    my ($self) = @_;

    my $schema = $self->result_source->schema;
    my $provider_src = $schema->resultset('Provider')->result_source;
    # provider's columns
    my @pcols_as = $provider_src->columns;
    # provider's columns prefixed with provider.
    my @pcols_sel = map { 'provider.' . $_ } @pcols_as;

    # our columns
    my @cols = $self->result_source->columns;

    # select both provider's and our columns as a flat list
    return $self->search(undef, {
        select => [ @cols, @pcols_sel ],
        as     => [ @cols, @pcols_as ],
        join   => 'provider',
    });
}

=head2 create_with_provider

Create new provider and extended table records given a flat argument list.
Returns its id.

=cut

sub create_with_provider {
    my ($self, $params) = @_;

    my $schema = $self->result_source->schema;
    my $provider_rs = $schema->resultset('Provider');
    my $provider_src = $provider_rs->result_source;
    # provider's columns
    my @pcols = $provider_src->columns;

    # put columns(+vals) that beong to Provider in %provider_data
    #   and delete from %$params, leaving %$params with
    #   only columns(+vals) for the extended table
    my %provider_data;
    for my $col (@pcols) {
        $provider_data{$col} = delete $params->{$col} if exists $params->{$col};
    }

    # in a transaction, create a new provider record, get its ID,
    #   create our (extended table) record with its provider_id
    #   set to the same value
    my $id = 0;

    my $txn = $schema->txn_do(sub {
        my $provider_result = $provider_rs->create(\%provider_data);
        $id = $provider_result->get_column('provider_id');
        $params->{provider_id} = $id;
        $self->create($params);
    });

    return $id;
}

=head2 update_with_provider

Updates an existing provider and extended table records given a flat argument list.

=cut

sub update_with_provider {
    my ($self, $provider_id, $params) = @_;

    my $schema        = $self->result_source->schema;
    my $provider_rs   = $schema->resultset('Provider');
    my $provider_src  = $provider_rs->result_source;
    my @pcols = $provider_src->columns;  # provider's columns

    # put columns(+vals) that belong to Provider in %provider_data
    #   and delete from %$params, leaving %$params with
    #   only columns(+vals) for the extended table
    my %provider_data;
    for my $col (@pcols) {
        $provider_data{$col} = delete $params->{$col} if exists $params->{$col};
    }

    try {
        # in a transaction, look up the provider ID and update applicable fields
        my $txn = $schema->txn_do(sub {
            my $provider_row = $provider_rs->search({ 'me.provider_id' => $provider_id })->first;
            $provider_row->update(\%provider_data) if %provider_data;
            $self->update($params) if %$params;
        });
    }
    catch {
        die "Unable to update provider and subprovider: $_";
    };

    # TODO: implement exception handling
    return $provider_id;
}

=head2 average_assignment_size($who)

Returns average assignment size.
Adds column: assignments_avg

    param $who : (string) Source alias
    return     : (resultset) ResultSet containing average size of assignments

=cut

sub average_assignment_size {
    my ($self, $who) = @_;
    $who //= $self->current_source_alias;

    return $self->search(undef, {
        '+select' => [ { 'avg' => 'assignments.size', -as => 'assignments_avg' } ],
        join      => [qw( assignments provider )],
        group_by  => [ "${who}.provider_id", "assignments.assignmentgroup_id" ],
    });
}

=head2 adjusted_size($where, $agt, $who)

Apply the overcommit ratio with the precedence defined in the AGT's overcommit property.
Columns: adjusted_size

    param $where : (Str) provider.provider_id = $where clause
    param $agt   : (Str) Assignment Group Type name
    param $who   : (Str) Source alias override
    return       : (ResutlSet) Adds the adjusted_size column to the ResultSet

=cut

sub adjusted_size {
    my ($self, $where, $agt, $who) = @_;
    $who //= $self->current_source_alias;
    confess "adjusted_size called without an agt defined" unless defined $agt;

    my $agt_info = $self->get_agt_overcommit($agt, $who);

    return $self
        ->search( { 'provider.provider_id' => { -ident => $where } }, {
            '+select' => [
                {
                    # Apply steps from perldoc B<adjusted_size>
                    coalesce => $agt_info->{'+select'},
                    -as => 'overcommit',
                },
            ],
            '+as'     => [ 'overcommit' ],
            #join      => $agt_info->{join},
            join      => { provider => 'providertype' },
        })
        ->as_subselect_rs
        ->search({ 'provider.provider_id' => { -ident => $where } },
         {
            '+select' => [
                {
                    coalesce => [
                        "${who}.overcommit * provider.size",
                        'provider.size'
                    ],
                    -as => "adjusted_size",
                }
            ],
            '+as'     => [ 'adjusted_size' ],
            join      => 'provider',
        });
}

=head2 get_agt_overcommit($agt_name, $who)

Returns the overcommit queries for an AGT.

    param $agt_name      : (Str) AGT Name
    param $who           : (Str) Source/table alias OR provider ID
    param $include_alias : (Str) Include the table alias in the subquery
    return               : (ArrayRef) Queries to go in COALESCE

=cut

sub get_agt_overcommit {
    my ($self, $agt_name, $who, $include_alias) = @_;
    $include_alias //= 1;
    $who //= $self->current_source_alias;
    my $search = looks_like_number($who) ? $who : "${who}.provider_id";

    my $schema = $self->result_source->schema;
    my $agt = $schema->resultset('AssignmentGroup_Type')->find($agt_name);
    confess "No AGT found: $agt_name" unless $agt;

    my $ctr = 0;

    my (@select, @as);
    for my $oc_info (@{ $agt->definition->{overcommit} // [] }) {
        my ($name, $overcommit) = %$oc_info; # { overcommit_providertype: 'providertype.overcommit_ratio' }

        push @as, $name;

        if ($overcommit =~ /^\\&(\w+)/) {
            if ($self->can($1)) {
                my $subq = $self->$1($search, $include_alias ? $name : undef);
                my $query = $subq ? $subq->as_query : \"NULL";
                push @select, $query;
            }
            else {
                die "$1 is not a supported agt overcommit function";
            }
        }
        else {
            push @select, $overcommit;
        }
    }
    push @select, \'1';
    push @as,     'overcommit_default';

    return {
        '+select' => \@select,
        '+as'     => \@as,
        join      => $agt->definition->{overcommit_join} // [],
    };
}

=head2 named_resource_size($who)

Figure out the number of resources in a provider with named resources.
Named resource providers don't have overcommit.
Columns: named_resource_size

    param $who      : (string) Source alias override
    Return          : (resultset) Adds the named_resource_size column to the ResultSet

=cut

sub named_resource_size {
    my ($self, $where, $who) = @_;
    $who //= $self->current_source_alias;

    return $self
        ->search(
            {
                'resources.provider_id' => { -ident => $where },
                'resources.available_date' => { '<=' => time() },
            },
            {
                'select' => [
                    {
                        count => 'resources.provider_id',
                        -as => 'named_resource_size',
                    },
                    $where,
                ],
                'as'     => [ 'named_resource_size', $where ],
                join      => [ 'resources', 'provider' ],
                group_by  => $where,
            },
        );
}

=head2 assigned($who)

Returns total assignment size.
Adds column: assigned

    param $who : (string) Source alias
    return     : (resultset) ResultSet containing provider assigned size

=cut

sub assigned {
    my ($self, $who) = @_;
    $who //= $self->current_source_alias;

    return $self->search(undef, {
        '+select' => [
            { coalesce => [ "SUM(assignments.size)", "$who.provider.size" ], -as => 'assigned' },
        ],
        join      => [qw( assignments provider )],
        group_by  => "${who}.provider_id",
    });
}

=head2 get_correlated_assignment_total($where)

Gets the correlated assignment total for a provider.
Column: size


    return             : (resultset) ResultSet containing the total assignment size for a provider

=cut

sub get_correlated_assignment_total {
    my ($self, $where) = @_;

    return $self
        ->as_alias('me2')
        ->as_subselect_rs
        ->search({ 'me2.provider_id' => { -ident => $where } }, { join => 'provider' })
        ->search_related_rs('assignments')
        ->get_column('size')
        ->sum_rs;
}

=head2 get_correlated_unassigned($where)

Gets the correlated unassigned capacity for a provider.
Column: unassigned

    param $where : (Str) Name of the resource
    param $agt   : (Str) Assignment Group Type name
    return       : (ResultSet) ResultSet containing the unassigned capacity for a provider

=cut

sub get_correlated_unassigned {
    my ($self, $where, $agt) = @_;
    confess "get_correlated_unassigned called without an agt defined" unless defined $agt;

    return $self
        ->as_alias('me2')
        ->adjusted_size('me2.provider_id', $agt)
        ->as_subselect_rs
            ->search({
                'me2.provider_id' => { -ident => $where },
            }, {
                '+select' => [
                    {
                        coalesce => [
                            "( me2.adjusted_size - SUM(assignments.size))",
                            "me2.adjusted_size"
                        ], -as => 'unassigned'
                    },
                ],
                join      => [qw( assignments provider )],
                group_by  => [ 'adjusted_size' ],
        })
        ->get_column('unassigned');
}

=head2 get_correlated_unassigned_named($where)

Gets the correlated unassigned capacity for a provider with named resources.
Column: unassigned

    param $where : (Str) Name of the resource
    return       : (ResultSet) ResultSet containing the unassigned capacity for a provider

=cut

sub get_correlated_unassigned_named {
    my ($self, $where) = @_;

    return $self
        ->as_alias('nr')
        ->named_resource_size('nr.provider_id')
        ->as_subselect_rs
            ->search({
                'nr.provider_id' => { -ident => $where },
            }, {
                '+select' => [
                    {
                        coalesce => [
                            "( nr.named_resource_size - SUM(assignments.size))",
                            "nr.named_resource_size"
                        ], -as => 'unassigned'
                    },
                ],
                join      => [qw( assignments provider )],
                group_by  => [ 'named_resource_size' ],
        })
       ->get_column('unassigned');
}

=head2 get_correlated_assignment_group_count($where)

Calculates the number of assignment groups that are associated with a provider

    param $where : (Str) Name of the resources
    return       : (ResultSet) ResultSet containing the agcnt column (number of AssignmentGroups associated)

=cut

sub get_correlated_assignment_group_count {
    my ($self, $where) = @_;

    return $self
        ->as_alias('me2')
        ->as_subselect_rs
        ->search({ 'me2.provider_id' => { -ident => $where } }, { join => 'provider' })
        ->search_related_rs('assignments', undef, {
             select => [ { count => { distinct => 'assignmentgroup_id' }, -as => 'agcnt' } ],
             as     => [ 'agcnt' ],
         })
        ->get_column('agcnt');
}

=head2 get_correlated_active_assignment_group_count($where)

Calculates the number of active assignment groups that are associated with a provider

    param $where : (Str) Name of the resources
    return       : (ResultSet) ResultSet containing the agcnt column (number of active AssignmentGroups associated)

=cut

sub get_correlated_active_assignment_group_count {
    my ($self, $where) = @_;

    return $self
        ->as_alias('me2')
        ->as_subselect_rs
        ->search({ 'me2.provider_id' => { -ident => $where } }, { join => 'provider' })
        ->search_related_rs('assignments', undef, {
            select      => [ 'assignmentgroup_id' ],
            group_by    => [ 'assignmentgroup_id' ],
            having      => [ 'SUM(assignments.size)' => { '>', 0 } ],
         })
        ->as_subselect_rs
        ->search(undef, {
            select  => [{ count   => 'assignmentgroup_id' }],
            as      => [ 'agcnt' ],
        })
        ->get_column('agcnt');
}

=head2 get_correlated_agt_capacity($where, $agt, $size, $as_of_date)

Calculates the number of AssignmentGroups of a specific size could be added to a provider
Column: agcount

    param $where      : (Str) Name of the resource
    param $agt        : (Str) Assignment Group Type name
    param $size       : (Num) Size of the resource
    param $as_of_date : (Int) Capacity as-of date
    return            : (ResultSet) ResultSet containing the agcount column (number of AssignmentGroups that can be created)

=cut

sub get_correlated_agt_capacity {
    my ($self, $where, $agt, $size, $as_of_date) = @_;
    confess "get_correlated_agt_capacity called without an agt defined" unless defined $agt;

    my $asmt_sum;
    if (defined $as_of_date) {
        # Look for assignments as of $as_of_date
        $asmt_sum = "CASE WHEN assignments.created <= $as_of_date THEN assignments.size ELSE 0 END";
    }
    else {
        $asmt_sum = "assignments.size";
    }

    my $coalesce = sprintf("COALESCE(%s,%s)",
        "cast(((me2.adjusted_size - SUM($asmt_sum)) / $size) as int)",
        "cast((me2.adjusted_size / $size) as int)",
    );

    # If a provider is over-allocated, return 0, not a negative
    my $case = sprintf("CASE WHEN %s < 0 THEN 0 ELSE %s END",
        $coalesce, $coalesce,
    );

    return $self
        ->as_alias('me2')
        ->adjusted_size('me2.provider_id', $agt)
        ->as_subselect_rs
            ->search({
                'me2.provider_id' => { -ident => $where },
            }, {
                '+select' => [
                    {
                        '' => \$case,
                       -as => 'agcount'
                   },
                ],
            join        => [qw( assignments provider )],
            group_by    => [ 'adjusted_size' ],
        })
        ->get_column('agcount');
}

=head2 get_correlated_agt_capacity_nr($where)

Calculates the number of AssignmentGroups of a specific size could be added to a provider
Column: agcount

    param $where      : (Str) Name of the resource
    param $size       : (Num) Size of the resource
    param $as_of_date : (Int) Capacity as-of date
    return            : (ResultSet) ResultSet containing the agcount column (number of AssignmentGroups that can be created)

=cut

sub get_correlated_agt_capacity_nr {
    my ($self, $where, $size, $as_of_date) = @_;

    my $asmt_sum;
    if (defined $as_of_date) {
        # Look for assignments as of $as_of_date
        $asmt_sum = "CASE WHEN assignments.created <= $as_of_date THEN assignments.size ELSE 0 END";
    }
    else {
        $asmt_sum = "assignments.size";
    }

    my $coalesce = sprintf("COALESCE(%s,%s)",
        "cast(((nr.named_resource_size - SUM($asmt_sum)) / $size) as int)",
        "cast((nr.named_resource_size / $size) as int)",
    );

    # If a provider is over-allocated, return 0, not a negative
    my $case = sprintf("CASE WHEN %s < 0 THEN 0 ELSE %s END",
        $coalesce, $coalesce,
    );

    return $self
        ->as_alias('nr')
        ->named_resource_size('nr.provider_id')
        ->as_subselect_rs
            ->search({
                'nr.provider_id' => { -ident => $where },
            }, {
                '+select' => [
                    {
                        '' => \$case,
                       -as => 'agcount'
                   },
                   'network.provider_id',
                ],
            join        => [qw( assignments provider )],
            group_by    => [ 'named_resource_size' ],
        })
        ->get_column('agcount');
}

=head2 get_correlated_average_assignment($where)

Gets the correlated average assignment size for a provider.
Column: ${resource}_avg

    param \@containers : (arrayref) Relationship Path
    param \%placement  : (hashref) Placement request

    return             : (resultset) ResultSet containing the average assignment size for a provider

=cut

sub get_correlated_average_assignment {
    my ($self, $where) = @_;

    return $self
        ->as_alias('me2')
        ->search_related_rs('assignments', {
            'assignments.provider_id' => { -ident => 'me2.provider_id' },
        }, {
            select   => [ 'assignments.provider_id', { sum => 'assignments.size', -as => 'tmptotal' } ],
            as       => [ 'provider_id', 'tmptotal' ],
            group_by => [ 'assignmentgroup_id', 'assignments.provider_id' ],
        })
        ->as_subselect_rs
        ->search({
            'assignments.provider_id' => { -ident => $where } ,
        }, {
            select => [ { avg => 'tmptotal', -as => 'average' } ],
        });
}

=head2 overcommit_ratio_info($agt_name, $provider_id)

Returns overcommit ratio info as overcommit_* columns given an assignment group type name.

    param $agt_name    : (Str) Name of the Assignment Group Type
    param $provider_id : (Int) Provider ID
    return             : (ResultSet) RS with overcommit_* columns

=cut

sub overcommit_ratio_info {
    my ($self, $agt_name, $provider_id) = @_;

    die "agt required for overcommit_ratio_info" unless $agt_name;

    my $agt_info = $self->get_agt_overcommit($agt_name, $provider_id, 0);

    return $self->search(undef, {
        '+select' => $agt_info->{'+select'},
        '+as' => $agt_info->{'+as'},
        join => $agt_info->{join},
    });
}

=head2 get_correlated_environment_overcommit()

Returns the provider type<=>environment overcommit ratio.
Column: overcommit_ratio

    return : (resultset) Adds the overcommit_ratio column to the ResultSet.

=cut

sub get_correlated_environment_overcommit {
    my ($self, $where, $who) = @_;
    $who //= $self->current_source_alias;

    return $self
        ->as_alias($who)
        ->search({
            'provider.providertype_name' => { -ident => 'defaults.providertype_name' },
            'provider.provider_id' => { -ident => $where },
        }, {
            select => 'defaults.overcommit_ratio',
            join   => { provider => { provider_environments => 'defaults' } },
        })
        ->get_column('defaults.overcommit_ratio')
        ->min_rs;
}

1;
