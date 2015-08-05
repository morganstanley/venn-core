package Swagger::Tools::Dependencies;
#-*- mode: CPerl;-*-

=head1 NAME

Swagger::Tools::Dependencies

=head1 DESCRIPTION

Swagger-related library dependency declarations.

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
use warnings;

our %DEPENDENCIES = (
    'PPI'                => '1.215',
    'Params-Util'        => '1.04',
    'Clone'              => '0.31',
    'List-MoreUtils'     => '0.33',
    'IO-String'          => '1.08',
    'Path-Class'         => '0.32',
    'JSON-XS'            => '3.01',
    'Types-Serialiser'   => '1.0',
    'common-sense'       => '3.6',
    'Tie-IxHash'         => '1.22',
    'Hash-Merge'         => '0.12',
    'Data-Walk'          => '1.00',
    'JSON-XS'            => '3.01',
    'Types-Serialiser'   => '1.0',
    'common-sense'       => '3.6',

    'Moo'                => '2.000001',
    'Module-Runtime'     => '0.014',# Used by Moo::_Utils, Method::Generate::Accessor
    'Devel-GlobalDestruction' => '0.11', # Used by Moo::_Utils, Moo::sification
    'Sub-Exporter-Progressive' => '0.001011',# Used by Devel::GlobalDestruction
    'Class-Load'         => '0.20', # Used by Class::MOP
    'Data-OptList'       => '0.108',# Used by Moose::Util, Class::MOP, Moose::Meta::Class, Class::Load, Class::Load
    'Sub-Install'        => '0.925',# Used by Data::OptList
    'Module-Implementation' => '0.07', # Used by Class::Load, Class::Load
    'Try-Tiny'           => '0.22', # Used by Moose::Util, Class::MOP::Class, Class::MOP::Method::Constructor, Class::Load, Class::Load, Class::MOP::Attribute, Moose::Object, Moose::Meta::Attribute, Moose::Meta::TypeConstraint
    'Sub-Name'           => '0.12', # Used by Class::MOP::Class, Class::MOP::Mixin::HasMethods, Moose::Exporter, Moose::Meta::TypeConstraint
    'Devel-OverloadInfo' => '0.002',# Used by Class::MOP::Mixin::HasOverloads
    'Package-Stash'      => '0.34', # Used by Devel::OverloadInfo
    'Sub-Identify'       => '0.10', # Used by Class::MOP::Mixin::HasOverloads
    'Eval-Closure'       => '0.13', # Used by Class::MOP::Method::Generated, Moose::Meta::TypeConstraint
    'Devel-Caller'       => '2.06', # Used by Devel::LexAlias
    'PadWalker'          => '2.0',  # Used by Devel::Caller
    'Package-DeprecationManager' => '0.11', # Used by Class::MOP::Deprecated
    'Params-Util'        => '1.07',# Used by Moose::Util
    'Sub-Exporter'       => '0.987',# Used by Moose::Util
    'List-MoreUtils'     => '0.410',# Used by Moose::Exporter, Moose::Meta::Class, Moose::Meta::Role::Application::ToClass
    'Exporter-Tiny'      => '0.042',# Used by List::MoreUtils
    'namespace-clean'    => '0.24', # Used by Devel::PartialDump
    'B-Hooks-EndOfScope' => '0.14', # Used by namespace::clean
    'MooX-ClassAttribute' => '0.010',
    'Role-Tiny'          => '2.000000',
    'Class-Method-Modifiers' => '2.04',
);

eval 'use Swagger::Tools::LocalDependencies'; ## no critic BuiltinFunctions::ProhibitStringyEval

=head1 AUTHOR

Venn Engineering

=cut

1;
