package Venn::Schema::ResultSet::Assignment;

=head1 NAME

package Venn::Schema::ResultSet::Assignment

=head1 DESCRIPTION

Base resultset for Assignment

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

use 5.010;
use Data::Dumper;

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;

extends 'Venn::SchemaBase::ResultSet';

=head1 METHODS

=head2 group_by_assignmentgroup_id($id, $sum, $committed)

Find sum of assignments grouped by resource for the assignmentgroup

    param $id        : (Int) ID of the assignmentgroup
    param $sum       : (Num) Where the sum is equal to this value
    param $committed : (Bool) Only look at committed assignments
    return           : (ResultSet) Assignments RS

=cut

# TODO: this should probably take %opts or \%opts
sub group_by_assignmentgroup_id {
    my ($self, $id, $sum, $committed) = @_;

    #$sum //= { '>' => \'0' };
    if (defined $sum) {
        $sum = "= $sum";
    }
    else {
        $sum = "> 0";
    }
    $committed //= 0;
    my %where;
    $where{committed} = { '>' => 0 } if $committed;
    $where{assignmentgroup_id} = $id if $id;
    return $self->search(
        \%where,
        {
            select      => [ 'me.provider_id', 'provider.providertype_name', 'me.resource_id', 'me.assignmentgroup_id', { sum => 'me.size', -as => 'total' } ],
            as          => [ 'provider_id', 'providertype_name', 'resource_id', 'assignmentgroup_id', 'total' ],
            join        => [ 'provider' ],
            group_by    => [ 'me.provider_id', 'provider.providertype_name', 'me.resource_id', 'assignmentgroup_id' ],
            having      => \[ "sum(me.size) $sum" ]
        },
    );
}

=head2 find_by_resource_id($id)

Find assignment by resource_id for a named resource

    param $id   : (Int) ID of the named resource
    return      : (Result) Assignment

=cut

sub find_by_resource_id {
    my ($self, $id) = @_;

    return $self->search({
        resource_id => $id,
    })->first();
}

=head2 search_by_assignmentgroup_id($id)

Retrieve assigments by assignmentgroup_id

    param $id           : (Int) ID of the Assignment Group
    return              : (ResultSet) Assignments

=cut

sub search_by_assignmentgroup_id {
    my ($self, $id) = @_;

    return $self->search( { assignmentgroup_id => $id } );
}


=head2 search_by_commit_group_id($commit_group_id)

Retrieve assigments by commit_group_id

    param $commit_id    : (Int) ID of commit group
    return              : (ResultSet) Assignments

=cut

sub search_by_commit_group_id {
    my ($self, $commit_group_id) = @_;

    return $self->search( { commit_group_id => $commit_group_id } );
}

=head2 search_uncommitted_by_commit_group_id($commit_group_id)

Retrieve uncommitted assigments by commit_group_id

    param $commit_id    : (Int) ID of commit group
    return              : (ResultSet) Assignments

=cut

sub search_uncommitted_by_commit_group_id {
    my ($self, $commit_group_id) = @_;

    return $self->search({
        commit_group_id => $commit_group_id,
        committed => 0,
    });
}

=head2 get_provider_total($assignmentgroup_id, $provider_id)

Find sum of assignments for given assignment group and provider

    param $assignmentgroup_id   : (Int) ID of the assignmentgroup
    param $provider_id          : (Int) ID of the provider
    return                      : (ResultSet) Assignments

=cut

sub get_provider_total {
    my ($self, $assignmentgroup_id, $provider_id) = @_;

    return $self->search(
        {
            assignmentgroup_id  => $assignmentgroup_id,
            'me.provider_id'    => $provider_id,
        },
        {
            select      => [ 'me.provider_id', { sum => 'me.size' } ],
            as          => [ 'provider_id', 'total' ],
            join        => [ 'provider' ],
            group_by    => [ 'me.provider_id' ],
        },
    );
}

1;
