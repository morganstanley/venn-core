package Moose::Meta::Attribute::Custom::Trait::SchemaClassAttr;

=head1 NAME

Moose::Meta::Attribute::Custom::Trait::SchemaClassAttr

=head1 DESCRIPTION

Adds the required_class_attr property to the attribute

=head1 SYNOPSIS

    class_has 'display_name' => (
        traits => [qw/ SchemaClassAttr /],
        is => 'rw',
        isa => 'Str',
        required_class_attr => 1,
        documentation => 'Display name when returning human readable text',
    );

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

use Moose::Role;

Moose::Util::meta_attribute_alias('SchemaClassAttr');

has required_class_attr => (
    is        => 'rw',
    isa       => 'Bool',
    predicate => 'is_required_class_attr',
    documentation => 'Requires that this class attribute is set before the call to __PACKAGE__->table()',
);

1;
