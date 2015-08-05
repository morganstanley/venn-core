package Venn::Schema::Result::Provider;

=head1 NAME

Venn::Schema::Result::Provider

=head1 DESCRIPTION

Provider base class. This describes something that provides some
sort of resource, such as cpu, memory, storage or i/o.

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
extends 'Venn::SchemaBase::Result';
with qw(
    Venn::Role::Logging
    Venn::SchemaRole::Result::Provider
    Venn::SchemaRole::Result::CommonClassAttributes
    Venn::SchemaRole::Result::ProviderAttributeHelpers
);

use Venn::Exception qw(
    API::InvalidAttributeType
);

use Scalar::Util qw( reftype );

__PACKAGE__->config(
    display_name    => 'Providers',
    primary_field   => 'provider_id',
);

__PACKAGE__->table("PROVIDERS");

__PACKAGE__->load_components(qw/Validator DefaultColumnValues/);

__PACKAGE__->add_columns(
    provider_id => {
        display_name  => 'Provider ID',
        data_type     => 'integer',
        is_auto_increment => 1,
        documentation => 'Identifier for this provider (PK)',
    },
    state_name => {
        display_name => 'State',
        is_foreign_key      => 1,
        data_type           => 'varchar',
        size                => 64,
        is_nullable         => 0,
        default_value_sub   => sub { return 'build'; },
        documentation       => 'Current state of this provider (locked, etc.)',
        validate       => sub {
            my ($profile, $state_name, $result, $schema) = @_;
            return $schema->resultset('Provider_State')->find($state_name) ? 1 : 0;
        },
        validate_error => 'Invalid provider state',
    },
    providertype_name => {
        display_name   => 'Provider Type',
        is_foreign_key => 1,
        data_type      => 'varchar',
        size           => 64,
        is_nullable    => 0,
        documentation  => 'Type of provider (memory, storage, etc.)',
    },
    available_date => {
        display_name  => 'Available Date',
        data_type     => 'integer',
        is_nullable   => 0,
        documentation => 'The date when this provider is able to be used',
    },
    size => {
        display_name  => 'Size',
        data_type     => 'decfloat',
        is_nullable   => 0,
        documentation => 'Size of this provider',
    },
    overcommit_ratio => {
        display_name  => 'Overcommit Ratio',
        data_type     => 'decfloat',
        is_nullable   => 1,
        documentation => 'Ratio used in allocation algorithm (1 is no overcommit)',
    },
);


__PACKAGE__->set_primary_key('provider_id');

__PACKAGE__->indices({
    prov_pk_idx    => [qw( provider_id )],
    prov_sort_idx  => [qw( state_name available_date provider_id )], # recommended
    prov_state_idx => [qw( state_name )],
    prov_type_idx  => [qw( providertype_name )],
    prov_size_idx  => [qw( size )],
    prov_avail_idx => [qw( available_date )],
    prov_or_idx    => [qw( overcommit_ratio )],
});

__PACKAGE__->belongs_to(
    'state' => 'Venn::Schema::Result::Provider_State',
    'state_name',
    {
        proxy => [ { state_description => 'description' } ],
        on_delete => 'restrict',
        on_update => 'restrict',
    },
);

__PACKAGE__->belongs_to(
    'providertype' => 'Venn::Schema::Result::Provider_Type',
    'providertype_name',
    {
        proxy => [
            'unit',
            'category',
            'subtable_name',
            { type_overcommit_ratio => 'overcommit_ratio' },
            { type_description => 'description' },
        ],
        on_delete => 'restrict',
        on_update => 'restrict',
    },
);

__PACKAGE__->has_many(
    'assignments' => 'Venn::Schema::Result::Assignment',
    'provider_id',
);

1;
