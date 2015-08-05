package Venn::SchemaRole::Result::ProviderAttributeHelpers;

=head1 NAME

package Venn::Schema::ResultSet::ProviderAttributeHelpers

=head1 DESCRIPTION

Role for Provider to handle adding attributes

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

=head1 METHODS

=cut

use Moose::Role;

use Venn::Exception qw(
    API::InvalidAttribute
);

=head2 map_attributes(\%attributes)

Maps attributes to the provider.

    $provider->map_attributes({
        owner       => [ 13131, 10233 ],
        environment => [qw/ dev qa /],
        capability  => 'ibm',
    });

    param \%attributes : (HashRef) Attributes and values

=cut

sub map_attributes {
    my ($self, $attrs) = @_;

    my $i = 0;
    for my $type (keys %$attrs) {
        my $value = $attrs->{$type};
        next unless defined $value;

        my $mapped_attrs = $self->mapped_attributes_of_type($type);

        # allow passing an array or a single item
        my @values = ref $value eq 'ARRAY' ? @$value : $value;
        for my $single_value (@values) {
            $self->log->trace("is $single_value ~~ (" . join(',', @$mapped_attrs) . ")");
            $self->map_attribute($type, $single_value) unless $single_value ~~ @$mapped_attrs;
        }
    }
    return;
}

=head2 map_attribute($type, $value)

Maps an attribute to the provider.

    $provider->map_attribute('environment', 'dev');

    param $type  : (Str) attribute type (e.g. environment)
    param $value : (Str) attribute value (e.g. dev)

=cut

sub map_attribute {
    my ($self, $type, $value) = @_;

    return unless defined $value;

    my $attr_info = Venn::Schema->attribute_info($type);
    my $pluralized_type = $attr_info->{plural};
    my $add_method = 'add_to_' . $pluralized_type;
    if ($self->can($add_method)) {
        my $row = $self->result_source->schema->resultset($attr_info->{source})->find($value);
        Venn::Exception::API::InvalidAttribute->throw({ attribute => $value, attributetype => $type }) unless $row;
        $self->$add_method($row);
    }
    else {
        Venn::Exception::API::InvalidAttributeType->throw({
            attributetype => $type,
            message => 'Attribute has not been configured',
        });
    }
    return;
}

=head2 unmap_attributes(\%attributes)

Unmaps attributes from the provider.

    $provider->unmap_attributes({
        owner        => [ 13131, 10233 ],
        environments => [qw/ dev qa /],
        capabilities => 'ibm',
    });

    param \%attributes : (HashRef) Attributes and values

=cut

sub unmap_attributes {
    my ($self, $attrs) = @_;

    my $i = 0;
    for my $type (keys %$attrs) {
        my $value = $attrs->{$type};
        next unless defined $value;

        my $mapped_attrs = $self->mapped_attributes_of_type($type);

        # allow passing an array or a single item
        my @values = ref $value eq 'ARRAY' ? @$value : $value;
        for my $single_value (@values) {
            $self->log->trace("is $single_value ~~ (" . join(',', @$mapped_attrs) . ")");
            $self->unmap_attribute($type, $single_value) if $single_value ~~ @$mapped_attrs;
        }
    }
    return;
}

=head2 unmap_attribute($type, $value)

Unmaps an attribute from the provider.

    $provider->unmap_attribute('environment', 'dev');

    param $type  : (Str) attribute type (e.g. environment)
    param $value : (Str) attribute value (e.g. dev)

=cut

sub unmap_attribute {
    my ($self, $type, $value) = @_;

    return unless defined $value;

    my $attr_info = Venn::Schema->attribute_info($type);
    my $pluralized_type = $attr_info->{plural};
    my $del_method = 'remove_from_' . $pluralized_type;
    if ($self->can($del_method)) {
        my $row = $self->result_source->schema->resultset($attr_info->{source})->find($value);
        Venn::Exception::API::InvalidAttribute->throw({ attribute => $value, attributetype => $type }) unless $row;
        $self->$del_method($row);
    }
    else {
        Venn::Exception::API::InvalidAttributeType->throw({
            attributetype => $type,
            message => 'Attribute has not been configured',
        });
    }
    return;
}

=head2 mapped_attributes_of_type($type)

Returns the mapped attributes of a specific type.

e.g. return [qw/ dev qa /] for type 'environment'

    param $type : (Str) Attribute Type
    return      : (ArrayRef) Mapped attribute values

=cut

sub mapped_attributes_of_type {
    my ($self, $type) = @_;

    my @attributes;

    my $attr_info = Venn::Schema->attribute_info($type);
    my $pluralized_type = $attr_info->{plural};
    my @mapped_attr_values = $self->$pluralized_type;
    if (scalar @mapped_attr_values > 0) {
        my @primary_cols = $mapped_attr_values[0]->primary_columns;
        if (scalar @primary_cols > 0) {
            my $primary_col = $primary_cols[0];
            @attributes = map { $_->$primary_col } @mapped_attr_values;
        }
    }

    return \@attributes;
}

=head2 get_attribute_info($type, $value1)

    param $type  : (Str) Attribute type
    param $value : (Str) Attribute value
    return       : (Result) Attribute resultset

=cut

sub get_attribute_info {
    my ($self, $type, $value) = @_;

    my $attr_info = Venn::Schema->attribute_info($type);
    my $mapped_attrs = $self->mapped_attributes_of_type($type);
    if ($value ~~ @$mapped_attrs) {
        return $self->result_source->schema->resultset($attr_info->{source})->find($value);
    }
}

1;
