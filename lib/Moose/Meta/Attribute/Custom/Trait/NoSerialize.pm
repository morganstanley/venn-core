package Moose::Meta::Attribute::Custom::Trait::NoSerialize;

=head1 NAME

Moose::Meta::Attribute::Custom::Trait::NoSerialize

=head1 DESCRIPTION

Adds a trait that signifies the attribute should not be serialized.

=head1 SYNOPSIS

    class_has 'log' => (
        traits        => [qw( NoSerialize )],
        is            => 'ro',
        isa           => 'Log::Log4perl::Logger',
        init_arg      => undef,
        default       => sub { Log::Log4perl::get_logger(__PACKAGE__) },
        documentation => 'Logger',
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

Moose::Util::meta_attribute_alias('NoSerialize');

1;
