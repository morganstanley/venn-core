package Venn::Schema::Result::Provider_Type;

=head1 NAME

Venn::Schema::Result::Provider_Type

=head1 DESCRIPTION

This table is used to map the base Provider class
with its subclasses (P_*).

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
    display_name => 'Provider Types',
    primary_field => 'providertype_name',
);
__PACKAGE__->table("PROVIDER_TYPES");

__PACKAGE__->add_columns(
    providertype_name => {
        data_type     => 'varchar',
        is_nullable   => 0,
        size          => 64,
    },
    category => {
        display_name  => 'Category',
        data_type     => 'varchar',
        is_nullable   => 0,
        size          => 64,
        documentation => 'Category of provider (cpu, memory, storage, etc.)',
    },
    description => {
        display_name  => 'Description',
        data_type     => 'varchar',
        is_nullable   => 0,
        size          => 255,
        documentation => 'Description of the provider type',
    },
    unit => {
        display_name  => 'Unit',
        data_type     => 'varchar',
        size          => 64,
        is_nullable   => 0,
        documentation => 'Unit this provider measures (MHz, GB, etc.)',
    },
    overcommit_ratio => {
        display_name  => 'Overcommit Ratio',
        data_type     => 'decfloat',
        is_nullable   => 1,
        documentation => 'Overcommit ratio for this provider type (1.0 = none)',
    },
);

__PACKAGE__->set_primary_key('providertype_name');

__PACKAGE__->indices({
    provtype_pk_idx   => [qw( providertype_name )],
    provtype_unit_idx => [qw( unit )],
    provtype_or_idx   => [qw( overcommit_ratio )],
});

__PACKAGE__->has_many(
    'providers' => 'Venn::Schema::Result::Provider',
    'providertype_name'
);

1;
