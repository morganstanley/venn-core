package Venn::Schema::Result::AssignmentGroup_Type;

=head1 NAME

Venn::Schema::Result::AssignmentGroup_Type

=head1 DESCRIPTION

This table describes how to create an AssignmentGroup via its definition.

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

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;
extends 'Venn::SchemaBase::Result';
with 'Venn::SchemaRole::Result::CommonClassAttributes';

__PACKAGE__->config(
    display_name  => 'Assignment Group Types',
    primary_field => 'name',
);

__PACKAGE__->table("ASSIGNMENT_GROUP_TYPES");

__PACKAGE__->load_components(qw/ InflateColumn::Serializer Validator /);

__PACKAGE__->add_columns(
    assignmentgroup_type_name => {
        display_name  => 'Name',
        data_type     => 'varchar',
        size          => 64,
        is_nullable   => 0,
        documentation => 'Name of the agt',
    },
    description => {
        display_name  => 'Description',
        data_type     => 'varchar',
        size          => 255,
        is_nullable   => 0,
        documentation => 'Description of the agt',
    },
    definition => {
        display_name     => 'Definition',
        data_type        => 'clob',
        size             => 32768,
        is_nullable      => 0,
        serializer_class => 'YAMLXS',
        documentation    => 'Definition of the agt (providertypes, joins, etc.)',
    },
);

__PACKAGE__->set_primary_key('assignmentgroup_type_name');

__PACKAGE__->add_unique_constraint( uc_name => [qw/ assignmentgroup_type_name /] );

__PACKAGE__->indices({
    agt_pk_idx => [qw( assignmentgroup_type_name )],
});

__PACKAGE__->has_many(
    'assignment_groups' => 'Venn::Schema::Result::AssignmentGroup',
    'assignmentgroup_type_name',
);

__PACKAGE__->meta->make_immutable(inline_constructor => 0);

__END__

=head1 DEFINITION EXAMPLE

    my %zlight_definition = (
        # base relationship name
        me             => 'esxram',
        # base provider class
        provider_class => 'P_Memory_Esx_Cluster',
        # root container class
        root_container_class => 'C_Rack',
        # root container alias
        root_container_alias => 'rack',
        # list of all relationships
        providers      => {
            esxram  => [ 'cluster' ],
            esxcpu  => [ 'cluster' ],
            nas     => [ 'cluster', 'rack', 'filers' ],
            filerio => [ 'cluster', 'rack', 'filers' ],
        },
        # where to find location parameters
        location       => {
            organization => ['rack'],
            hub          => ['rack'],
            continent    => ['rack'],
            country      => ['rack'],
            campus       => ['rack'],
            city         => ['rack'],
            building     => ['rack'],
        },
        provider_to_location_join => {
            esxram  => { 'cluster' => 'rack' },
            esxcpu  => { 'cluster' => 'rack' },
            nas     => { 'filer'   => 'rack' },
            filerio => { 'filer'   => 'rack' },
        },
        # join clause for DBIC to get all the above info
        join_clause      => [
            { 'cluster' => { 'rack' => { 'filers' => ['nas', 'filerio'] } } },
            'esxcpu',
            'esxram',
        ],
        place_format => 'Placed on cluster %s, share %s, filer %s',
        place_args   => [qw( esxcpu.cluster_name nas.share_name filerio.filer_name )],
    );
