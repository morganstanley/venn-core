package Venn::SchemaRole::Result::Host;

=head1 NAME

package Venn::Schema::ResultSet::Host

=head1 DESCRIPTION

Role for Host provider

=cut

use Moose::Role;

sub hosts_of_webpool {
    my ($self) = @_;

    my @hosts = $self->webpool->hosts->as_hash->all;
    @hosts = map {$_->{hostname}} @hosts;

    return @hosts;
}

1;
