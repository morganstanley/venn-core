package Venn::Controller::API::v1;

=head1 NAME

Venn::Controller::v1 - Base Controller for Venn API Version 1

=head1 DESCRIPTION

Base controller for Venn api v1.

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
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::REST' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(
    namespace => 'api/v1',
    default => 'application/json',
    stash_key => 'rest',
    map => {
        'application/json' => 'JSON',
        'text/x-yaml' => 'YAMLXS',
        'text/html' => 'TextHtml',
    }
);

=head1 AUTHOR

Venn Engineering

=cut

__PACKAGE__->meta->make_immutable;
