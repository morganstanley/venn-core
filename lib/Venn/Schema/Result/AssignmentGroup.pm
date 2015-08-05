package Venn::Schema::Result::AssignmentGroup;

=head1 NAME

Venn::Schema::Result::AssignmentGroup

=head1 DESCRIPTION

An Assignment Group is a set of Assignments representing a single object.

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
use Data::UUID;

extends 'Venn::SchemaBase::Result';
with qw(
    Venn::SchemaRole::Result::AssignmentGroup
    Venn::SchemaRole::Result::CommonClassAttributes
    Venn::Role::Logging
);

__PACKAGE__->config(
    # NOTE: just friendly alone is not enough to fully
    #       qualify an AssignmentGroup
    #       the primary key: assignmentgroup_id is
    #              OR
    #       assignmentgrptype_id && friendly
    #              OR
    #       assignmentgrptype_id && identifier
    primary_field => 'friendly',
    display_name  => 'Assignment Groups',
);

__PACKAGE__->load_components(qw/ InflateColumn::Serializer Validator DefaultColumnValues /);
__PACKAGE__->table("ASSIGNMENT_GROUPS");

__PACKAGE__->add_columns(
    assignmentgroup_id => {
        display_name      => 'Assignment Group ID',
        is_auto_increment => 1,
        data_type         => 'integer',
        documentation     => 'ID for this Assignment Group',
    },
    assignmentgroup_type_name => {
        display_name   => 'Assignment Group Type',
        is_foreign_key => 1,
        data_type      => 'varchar',
        size           => 64,
        is_nullable    => 0,
        documentation  => 'AssignmentGroup_Type name',
    },
    friendly => {
        display_name  => 'Friendly',
        data_type     => 'varchar',
        size          => 128,
        is_nullable   => 1,
        documentation => 'Friendly lookup ID (hostname, etc.)',
    },
    identifier => {
        display_name  => 'Identifier',
        data_type     => 'varchar',
        size          => 36,
        is_nullable   => 0,
        documentation => 'Identifier (expected from remote caller)',
    },
    metadata => {
        display_name     => 'Metadata',
        data_type        => 'clob',
        size             => 32768,
        is_nullable      => 1,
        serializer_class => 'YAMLXS',
        documentation    => 'Misc. storage',
    },
    created => {
        display_name      => 'Created',
        data_type         => 'integer',
        is_nullable       => 0,
        default_value_sub => sub { time() },
        documentation     => 'When the assignment was created',
    },
);

__PACKAGE__->set_primary_key('assignmentgroup_id');

__PACKAGE__->add_unique_constraint( uc_name => [qw/ assignmentgroup_type_name identifier /] );

__PACKAGE__->indices({
    ag_friendly_idx   => [qw( friendly )],
    ag_identifier_idx => [qw( identifier )],
    ag_created_idx    => [qw( created )],
});

__PACKAGE__->has_many(
    'assignments' => 'Venn::Schema::Result::Assignment',
    'assignmentgroup_id',
);
__PACKAGE__->belongs_to(
    'assignment_group_type' => 'Venn::Schema::Result::AssignmentGroup_Type',
    'assignmentgroup_type_name',
    {
        on_delete => 'restrict',
        on_update => 'restrict',
    }
);


__PACKAGE__->meta->make_immutable(inline_constructor => 0);
