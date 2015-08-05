package Venn::SchemaRole::AutoDeploy;

=head1 NAME

Venn::SchemaRole::AutoDeploy

=head1 DESCRIPTION

Auto-deploy the DB Schema for the testsuite

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
use Moose::Role;

=head2 after connection

For standalone Catalyst tests (CLI commands), we need to preserve the schema
Catalyst is connected to currently, thus test suite could deploy database content.

=cut

after 'connection' => sub {
    my $self = shift;

    # autodeploy database for tests
    if ($ENV{VENN_TEST_DB_AUTODEPLOY}) {
        eval { require 't/Autodeploy.pm'; t::Autodeploy->execute($self) }; ## no critic Modules::RequireBarewordIncludes
        if (my $err = $@) {
            warn __PACKAGE__." failed: $err";
        }
    }

    return $self;
};



1;
