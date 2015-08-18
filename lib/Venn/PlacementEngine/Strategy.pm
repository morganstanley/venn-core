package Venn::PlacementEngine::Strategy;

=head1 NAME

Venn::PlacementEngine::Strategy

=head1 DESCRIPTION

Base class for a placement strategy. Contains the schema, request, result, and
other options given to the Placement Engine.

See: L<Venn::PlacementEngine>

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
use MooseX::ClassAttribute;
use Moose::Util qw( ensure_all_roles );
with 'Venn::Role::Logging';
use namespace::autoclean;

use TryCatch;
use Log::Log4perl;
use Data::Dumper;
use Data::UUID;

use Venn::Types qw(:all);
use Venn::PlacementEngine::Request;
use Venn::PlacementEngine::Result;
use Venn::Exception qw(
    API::InvalidRequestResource
);

has 'schema' => (
    is            => 'ro',
    isa           => 'Venn::Schema',
    required      => 1,
    documentation => 'Venn Schema object',
);

has 'request' => (
    is            => 'ro',
    isa           => 'Venn::PlacementEngine::Request',
    required      => 1,
    documentation => 'Placement Request',
);

has 'assignment_group' => (
    is            => 'ro',
    isa           => 'Maybe[Str]',
    required      => 0,
    documentation => 'Identifier for when placing to an existing assignment group',
);

has 'commit_group_id' => (
    is            => 'ro',
    isa           => 'Maybe[Str]',
    required      => 0,
    documentation => 'Commit group identifier, if needed'
);

has 'result' => (
    is            => 'ro',
    isa           => 'Venn::PlacementEngine::Result',
    init_arg      => undef,
    lazy          => 1, # required for default to work
    default       => sub { Venn::PlacementEngine::Result->new(strategy => $_[0]) },
    documentation => 'Placement Result',
);

has 'all_rows' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    documentation => 'Return all possible placement locations',
);

has 'simulate' => (
    is            => 'ro',
    isa           => 'Bool',
    default       => 0,
    documentation => "Simulate placement (don't create an Assignment Group)",
);

has 'definition' => (
    is            => 'rw',
    isa           => 'HashRef',
    documentation => 'Definition of the Assignment Group Type',
);

class_has '_ug' => (
    is            => 'ro',
    isa           => 'Log::Log4perl::Logger',
    init_arg      => undef,
    default       => sub { Data::UUID->new() },
    handles       => {
        generate_uuid => 'create_str',
    },
    documentation => 'Data::UUID UUID generator object',
);

=head1 METHODS

=head2 BUILD()

Builds the definition immediately.

=cut

sub BUILD {
    my ($self) = @_;

    $self->_build_definition();

    return;
}


=head2 _build_definition()

Retrieves the definition and ID of an Assignment Group Type.

NOTE: See __DATA__ section for a definition example.

=cut

sub _build_definition {
    my ($self) = @_;

    try {
        my $row = $self->schema->resultset('AssignmentGroup_Type')
            ->single({ assignmentgroup_type_name => $self->request->assignmentgroup_type });
        if ($row) {
            $self->definition($row->definition);
        }
        else {
            # TODO: exception
            die "Can't find the AssignmentGroup Type";
        }
    }
    catch ($err) {
        die sprintf("Can't retrieve the AssignmentGroup Type: %s (%s)", $self->request->assignmentgroup_type, $err);
    }
}


=head2 place()

Places based on a placement request, returns a placement result.

TODO: describe process in steps

    return : (Venn::PlacementEngine::Result) placement result

=cut

sub place {
    my ($self) = @_;

    $self->schema->txn_do(
        sub {
            #locks assignments table if db2 ( concurrency )
            $self->schema->resultset('Assignment')->lock_table();

            $self->schema->lower_optimization_class(); # db2 fix

            # Call the augmented place to get a placement resultset
            my $placement_rs = inner();

            # Verify that the placement strategy set a placement resultset
            Venn::Exception::API::BadPlacementResult->throw({
                result => $placement_rs,
                reason => "The Placement Engine did not return a result",
            }) unless defined $placement_rs;

            # Once this is set, a trigger is called in the result to finalize the placement
            $self->result->placement_rs($placement_rs);

            $self->schema->raise_optimization_class(); # db2 fix
        }
    );

    return $self->result;
}


=head2 helpers(@helpers)

Used in strategies to load helper roles.

=cut

sub helpers {
    my ($self, @helpers) = @_;

    return ensure_all_roles($self, map { "Venn::PlacementEngine::Helper::$_" } @helpers);
}

=head2 validate_request_resources($request)

Validates resources if they were part of the AGT definition (valid providers bound to this AGT)
Raises an exception if not.

=cut

sub validate_request_resources {
    my ($self, $request) = @_;

    my @valid_resources = keys %{$self->definition->{providers}};

    for my $resource (keys %{$request->{resources}}) {
        unless ($resource ~~ @valid_resources) {
            Venn::Exception::API::InvalidRequestResource->throw({
                resource => $resource,
            });
        }
    }

    return 1;
}

1;
