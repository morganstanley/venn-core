package Venn::SchemaRole::Result::Validator_Basic;

=head1 NAME

package Venn::SchemaRole::Result::Validator_Basic

=head1 DESCRIPTION

Basic, regex-based validator functions for testing

=cut

use Moose::Role;

sub ip_address {
    my ($profile, $val) = @_;

    return $val =~ m/\d+\.\d+\.\d+\.\d+/;
}

sub ports_min {
    my ($profile, $val) = @_;

    return $val >= 2**10;
}

sub ports_max {
    my ($profile, $val) = @_;

    return $val < 2**16;
}

sub ports_non_negative {
    my ($profile, $val) = @_;

    return $val > 0;
}

sub valid_rack {
    return 1;
}

1;
