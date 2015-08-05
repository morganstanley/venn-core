package Venn::Schema::Result::Provider_State;

=head1 NAME

Venn::Schema::Result::Provider_State

=head1 DESCRIPTION

This table contains the various states that a provider may be in
such as build, created, active, inactive, etc.

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
    display_name  => 'Provider States',
    primary_field => 'state_name',
);
__PACKAGE__->table("PROVIDER_STATES");

__PACKAGE__->load_components(qw/Validator/);

__PACKAGE__->add_columns(
    state_name => {
        display_name  => 'State',
        data_type     => 'varchar',
        is_nullable   => 0,
        size          => 64,
        documentation => 'State (e.g. build, created, active, inactive, etc.)',
    },
    description => {
        display_name  => 'Description',
        data_type     => 'varchar',
        is_nullable   => 1,
        size          => 255,
        documentation => 'Description of the state',
    },
);

__PACKAGE__->set_primary_key('state_name');

__PACKAGE__->indices({
    provstate_pk_idx => [qw( state_name )],
});

__PACKAGE__->has_many(
    'providers' => 'Venn::Schema::Result::Provider',
    'state_name'
);

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
