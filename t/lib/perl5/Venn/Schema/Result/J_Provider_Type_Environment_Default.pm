package Venn::Schema::Result::J_Provider_Type_Environment_Default;

=head1 NAME

Venn::Schema::Result::J_Provider_Type_Environment_Default

=head1 DESCRIPTION

Join table for Provider_Type and Environments, containing defaults per pair

=cut

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;
extends 'Venn::SchemaBase::Result';
with 'Venn::SchemaRole::Result::CommonClassAttributes';

__PACKAGE__->config(
    display_name => 'Provider Type Environment Defaults',
    primary_field => 'providertype_name,environment',
);

__PACKAGE__->table("J_PROVIDER_TYPE_ENVIRONMENT_DEFAULTS");

__PACKAGE__->add_columns(
    providertype_name => {
        display_name   => 'Provider Type',
        is_foreign_key => 1,
        data_type      => 'varchar',
        is_nullable    => 0,
        size           => 64,
        documentation  => 'Provider Type FK',
    },
    environment => {
        display_name   => 'Environment',
        is_foreign_key => 1,
        data_type      => 'varchar',
        is_nullable    => 0,
        size           => 32,
        documentation  => 'Environment FK',
    },
    overcommit_ratio => {
        display_name  => 'Overcommit Ratio',
        data_type     => 'decfloat',
        is_nullable   => 1,
        documentation => 'Overcommit Ratio (1.0 = no overcommit)',
    },
);

__PACKAGE__->set_primary_key(qw( providertype_name environment ));

__PACKAGE__->indices({
    j_provtypeenvdef_pk_idx => [qw( providertype_name environment )],
    j_provtypeenvdef_env_idx => [qw( environment )],
    j_provtypeenvdef_pt_idx => [qw( providertype_name )],
    j_provtypeenvdef_or_idx => [qw( overcommit_ratio )],
});

__PACKAGE__->belongs_to(
    'providertype' => 'Venn::Schema::Result::Provider_Type',
    'providertype_name',
    {
        on_delete => 'cascade',
        on_update => 'restrict',
    },
);
__PACKAGE__->belongs_to(
    'environment' => 'Venn::Schema::Result::A_Environment',
    'environment',
    {
        on_delete => 'cascade',
        on_update => 'restrict',
    },
);

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
