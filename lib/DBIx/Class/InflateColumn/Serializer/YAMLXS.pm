package DBIx::Class::InflateColumn::Serializer::YAMLXS;

=head1 NAME

DBIx::Class::InflateColumn::Serializer::YAMLXS - YAML::XS Inflator

=head1 SYNOPSIS

  package MySchema::Table;
  use base 'DBIx::Class';

  __PACKAGE__->load_components('InflateColumn::Serializer', 'Core');
  __PACKAGE__->add_columns(
    'data_column' => {
      'data_type' => 'VARCHAR',
      'size'      => 255,
      'serializer_class'   => 'YAML'
    }
  );

Then in your code...

  my $struct = { 'I' => { 'am' => 'a struct' };
  $obj->data_column($struct);
  $obj->update;

And you can recover your data structure with:

  my $obj = ...->find(...);
  my $struct = $obj->data_column;

The data structures you assign to "data_column" will be saved in the database in YAML format.

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

use strict;
use warnings;

use YAML::XS;
use Carp;

=head1 METHODS

=head2 get_freezer($column, $info, $args)

Called by DBIx::Class::InflateColumn::Serializer to get the routine that serializes
the data passed to it. Returns a coderef.

=cut

sub get_freezer {
    my ($class, $column, $info, $args) = @_;

    if (defined $info->{size}) {
        my $size = $info->{size};
        return sub {
            my $s = YAML::XS::Dump(shift);
            croak "serialization too big" if length($s) > $size;
            return $s;
        };
    }
    else {
        return sub {
            return YAML::XS::Dump(shift);
        };
    }
}

=head2 get_unfreezer()

Called by DBIx::Class::InflateColumn::Serializer to get the routine that deserializes
the data stored in the column. Returns a coderef.

=cut

sub get_unfreezer {
    return sub {
        return YAML::XS::Load(shift);
    };
}


1;
