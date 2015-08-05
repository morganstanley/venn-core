package Venn::SchemaRole::Result::ProviderTypeAttributes;

=head1 NAME

package Venn::Schema::ResultSet::ProviderTypeAttributes

=head1 DESCRIPTION

Role for provider subclasses (P_*)

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
use MooseX::ClassAttribute;

class_has 'providertype' => (
    traits => [qw/ SchemaClassAttr /],
    is => 'rw',
    isa => 'Str',
    required_class_attr => 1,
    documentation => 'Provider type name',
);

class_has 'container_field' => (
    traits => [qw/ SchemaClassAttr /],
    is => 'rw',
    isa => 'Str',
    required_class_attr => 1,
    documentation => 'Container field for this provider',
);

class_has 'container_class' => (
    traits => [qw/ SchemaClassAttr /],
    is => 'rw',
    isa => 'Str',
    required_class_attr => 1,
    documentation => 'Container class for this provider',
);

class_has 'named_resources' => (
    traits => [qw/ SchemaClassAttr /],
    is => 'rw',
    isa => 'Str',
    default => 0,
    required_class_attr => 1,
    documentation => 'Relationship to named resources, if supported.',
);

class_has 'named_resources_resourcename' => (
    traits => [qw/ SchemaClassAttr /],
    is => 'rw',
    isa => 'Str',
    default => 0,
    required_class_attr => 1,
    documentation => 'Name of resource identifier column in the resource table',
);

1;
