package Venn::Schema::Result::M_Port_Exclusion;

=head1 NAME

Venn::Schema::Result::M_Port_Exclusion

=head1 DESCRIPTION

Port exclusion storage for P_Ports_Host.

=cut

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;
use MooseX::ClassAttribute;
extends 'Venn::SchemaBase::Result';
with qw(
    Venn::SchemaRole::Result::CommonClassAttributes
);

__PACKAGE__->config(
    display_name    => 'Misc Resource: Port exclusion',
    primary_field   => 'resource_id',
);

__PACKAGE__->table("M_PORT_EXCLUSIONS");

__PACKAGE__->add_columns(
    resource_id => {
        display_name      => 'Resource ID',
        data_type         => 'integer',
        is_auto_increment => 1,
        documentation     => 'Resource ID',
    },
    hostname => {
        display_name    => 'Host',
        data_type       => 'varchar',
        is_nullable     => 1,
        size            => 64,
    },
    webpool_name => {
        display_name    => 'Webpool',
        data_type       => 'varchar',
        is_nullable     => 1,
        size            => 64,
    },
    continent => {
        display_name  => 'Continent',
        data_type     => 'varchar',
        is_nullable   => 1,
        size          => 2,
        documentation => 'Continent',
    },
    building => {
        display_name  => 'Building',
        data_type     => 'varchar',
        is_nullable   => 1,
        size          => 3,
        documentation => 'Building',
    },
    global  => {
        display_name  => 'Global',
        data_type     => 'int',
        is_nullable   => 1,
    },
    start_port => {
        display_name   => 'Port',
        data_type      => 'integer',
        is_nullable    => 0,
        documentation  => 'port on a host for exclusion',
        validate       => sub {
            my ($profile, $val) = @_;
            return $val < 2**16 && $val >= 2**10;
        },
        validate_error => 'currently support ports 1024-65535',
    },
    num_ports => {
        display_name   => 'Number of Ports',
        data_type      => 'integer',
        is_nullable    => 0,
        documentation  => 'Number of ports allocated',
        validate       => sub {
            my ($profile, $val) = @_;
            return $val > 0;
        },
        validate_error => 'non-negative num_ports required',
    },
);

__PACKAGE__->set_primary_key('resource_id');

__PACKAGE__->indices({
    "m_port_exclusion_pk_idx"         => ['resource_id'],
    "m_port_exclusion_hostname"       => ['hostname'],
    "m_port_exclusion_webpool_name"   => ['webpool_name'],
    "m_port_exclusion_continent"      => ['continent'],
    "m_port_exclusion_building"       => ['building'],
    "m_port_exclusion_global"         => ['global'],
});


__PACKAGE__->meta->make_immutable(inline_constructor => 0);
