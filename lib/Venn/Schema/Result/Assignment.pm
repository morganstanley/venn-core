package Venn::Schema::Result::Assignment;

=head1 NAME

Venn::Schema::Result::Assignment

=head1 DESCRIPTION

A single assignment of a mapping resources used (positive size)
or returned (negative size) to a specific provider.

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
use Moose;
use MooseX::NonMoose;
use namespace::autoclean;
extends 'Venn::SchemaBase::Result';
with 'Venn::SchemaRole::Result::CommonClassAttributes';

__PACKAGE__->config(
    display_name  => 'Assignment',
    primary_field => 'assignment_id',
);

__PACKAGE__->table("ASSIGNMENTS");

__PACKAGE__->load_components(qw/Validator DefaultColumnValues/);

__PACKAGE__->add_columns(
    assignment_id => {
        display_name      => 'Assignment ID',
        is_auto_increment => 1,
        data_type         => 'integer',
        documentation     => 'ID for this Assignment',
    },
    provider_id => {
        display_name   => 'Provider ID',
        is_foreign_key => 1,
        data_type      => 'integer',
        is_nullable    => 0,
        documentation  => 'ID of the Provider record this assignment provides',
    },
    assignmentgroup_id => {
        display_name   => 'Assignment Group ID',
        is_foreign_key => 1,
        data_type      => 'integer',
        is_nullable    => 0,
        documentation  => 'ID of the parent Assignment Group',
    },
    size => {
        display_name  => 'Size',
        data_type     => 'decfloat',
        is_nullable   => 0,
        documentation => 'Size of assignment',
    },
    resource_id => {
        display_name  => 'Resource ID',
        data_type     => 'integer',
        is_nullable   => 1,
        documentation => 'Optional key from proivder resource table',
    },
    created => {
        display_name      => 'Created',
        data_type         => 'integer',
        is_nullable       => 0,
        default_value_sub => sub { time() },
        documentation     => 'When the assignment was created',
    },
    committed => {
        display_name  => 'Committed',
        data_type     => 'integer',
        is_nullable   => 0,
        documentation => 'When assignment has been committed',
    },
    commit_group_id => {
        display_name  => 'Commit ID',
        data_type     => 'varchar',
        size          => '36',
        is_nullable   => 1,
        documentation => 'Identifier for a commit group',
    },
);

__PACKAGE__->set_primary_key('assignment_id');

__PACKAGE__->indices({
    asgnmnt_pk_idx         => [qw( assignment_id )],
    asgnmnt_sort_idx       => [qw( provider_id assignmentgroup_id )],
    asgnmnt_committed_idx  => [qw( committed )],
    asgnmnt_providerid_idx => [qw( provider_id )],
    asgnmnt_agid_idx       => [qw( assignmentgroup_id )],
    asgnmnt_cgt_idx        => [qw( commit_group_id )],
    asgnmnt_created_idx    => [qw( created )],
});

__PACKAGE__->belongs_to(
    'provider' => 'Venn::Schema::Result::Provider',
    'provider_id',
    {
        # TODO: protect providers from deletion (only super admins)
        #   make sure the sum of the assignments in assignmentgroups on this provider is 0
        #   LOCK TABLE when doing above ^
        #   regular admins can only change state_name to decommissioned
        on_delete      => 'cascade',
        on_update      => 'restrict',
    },
);
__PACKAGE__->belongs_to(
    'assignmentgroup' => 'Venn::Schema::Result::AssignmentGroup',
    'assignmentgroup_id',
    {
        on_delete      => 'cascade',
        on_update      => 'restrict',
        cascade_update => 1,
    },
);

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
