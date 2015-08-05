package Venn::SchemaBase::Result;

=head1 NAME

Venn::SchemaBase::Result

=head1 DESCRIPTION

Base Result source class for DBIC

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
use MooseX::ClassAttribute;
use namespace::autoclean;
extends 'DBIx::Class::Core';

use Scalar::Util qw( blessed reftype );
use Data::Dumper;

__PACKAGE__->load_components(qw[
    Helper::Row::ToJSON
    +DBIx::Class::Indexer
]);

class_has '_table_prefix' => (
    is => 'rw',
    isa => 'Str',
    default => sub { uc($ENV{VENN_TABLE_PREFIX} // '') },
    documentation => 'Table name prefix',
);

class_has '_table_suffix' => (
    is => 'rw',
    isa => 'Str',
    default => sub { uc($ENV{VENN_TABLE_SUFFIX} // '') },
    documentation => 'Table name suffix',
);

=head1 METHODS

=head2 around table($table_name)

Verifies that all required class attributes are set.
Prepends prefix and appends suffix to the table name.

=cut

around 'table' => sub {
    my ($orig, $self, $table) = @_;

    if ($table) {
        $self->_verify_required_config();
        return $self->$orig(__PACKAGE__->_table_prefix . $table . __PACKAGE__->_table_suffix);
    }
    else {
        return $self->$orig();
    }
};

=head2 config(%params)

Sugar method to set your class attributes using a hash.

    param %params : (hash) Hash of class attributes to set.

=cut

sub config {
    my ($self, %params) = @_;

    for my $param (keys %params) {
        my $value = $params{$param};
        if ($self->can($param)) {
            $self->$param($value);
        }
        else {
            # TODO: Exception
            die "Invalid config param: $param in " . ref($self) . "\n";
        }
    }

    return;
}

=item _verify_required_config()

Verifies that required class attributes are set.

=cut

sub _verify_required_config {
    my ($self) = @_;

    my @classattrs = $self->meta->get_all_class_attributes();
    for my $classattr (@classattrs) {
        my $name = $classattr->name;
        if ($classattr->does('Moose::Meta::Attribute::Custom::Trait::SchemaClassAttr')
            && $classattr->is_required_class_attr) {

          # This is a required class attribute
          chomp( my @isa = split /|/, $classattr->{isa} );
          next if ('Undef' ~~ @isa); # skip if can be undef

          # TODO: Exception
          die sprintf(
              "%s requires that '%s' is defined\n",
              $self, $name,
          ) unless defined $self->$name;
        }
    }

    return;
}

=head2 overload ""() a.k.a. TO_STRING

Stringifies into "Name of class: primary field"

=cut

use overload '""' => sub {
    my $self = shift;
    if (defined $self->primary_field) {
        my $primary_field = $self->primary_field;
        return (ref $self) . ': ' . $self->$primary_field();
    }
    else {
        return (ref $self);
    }
};

1;
