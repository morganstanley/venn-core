package Venn::Schema::ResultSet::M_Port_Exclusion;

=head1 NAME

package Venn::Schema::ResultSet::M_Port_Exclusion

=head1 DESCRIPTION

Base resultset for M_Port_Exclusion

=cut

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;

extends 'Venn::SchemaBase::ResultSet';


__PACKAGE__->meta->make_immutable(inline_constructor => 0);
