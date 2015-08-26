package Venn::PlacementEngine::Result;

=head1 NAME

Venn::PlacementEngine::Result

=head1 DESCRIPTION

This class describes a result from the Placement Engine. It handles the
output from the engine, creates human readable errors, and optionally creates
an AssignmentGroup and the associated Assignments

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
with qw(
    Venn::Role::Logging
    Venn::Role::SerializeAttrsToJSON
);
use namespace::autoclean;
use Moose::Util qw(ensure_all_roles);

use Venn::Types qw(:all);
use Venn::Exception qw(
    API::BadPlacementResult
    API::BadPlacementRequest
    Placement::InvalidAssignmentGroup
);

use TryCatch;
use Scalar::Util qw( reftype );

use MooseX::Types::Moose qw(Str ArrayRef HashRef Object Maybe);
use MooseX::Types::Structured qw(Map);

no if $] >= 5.018, warnings => q{experimental::smartmatch};

has 'strategy' => (
    traits        => [qw( NoSerialize )],
    handles       => [qw( schema generate_uuid )],
    is            => 'ro',
    isa           => 'Venn::PlacementEngine::Strategy',
    required      => 1,
    documentation => 'Placement Engine Strategy',
);

has 'request' => (
    is            => 'ro',
    isa           => 'Venn::PlacementEngine::Request',
    documentation => 'Placement Engine request object (here for serialization)',
);

has 'definition' => (
    is            => 'ro',
    isa           => HashRef,
    documentation => 'Definition of the Assignment Group Type (here for serialization)',
);

has 'state' => (
    is            => 'rw',
    isa           => PlacementResultState,
    default       => 'Pending',
    documentation => 'Current state of this result',
);

has 'error' => (
    is => 'rw',
    documentation => 'Error message (if not placed)',
);

has 'placement_message' => (
    is => 'rw',
    isa => 'Str',
    documentation => 'Placement message in English',
);

has 'placement_candidates' => (
    is            => 'rw',
    isa           => ArrayRef[HashRef],
    trigger       => \&_set_placement_location,
    documentation => 'Placement candidates in order of best to worst',
);

has 'placement_location' => (
    is            => 'rw',
    isa           => Maybe[HashRef],
    documentation => 'Placement location',
);

has 'placement_named_resources' => (
    is            => 'rw',
    isa           => HashRef,
    default       => sub { {} },
    documentation => 'Any named resources in the placement',
);

has 'placement_rs' => (
    traits        => [qw( NoSerialize )],
    is            => 'rw',
    isa           => Object,
    trigger       => \&_finalize_placement,
    documentation => 'Placement ResultSet',
);

has 'placement_info' => (
    is            => 'ro',
    isa           => HashRef,
    default       => sub { {} },
    documentation => 'Placement debug info',
);

has 'assignmentgroup' => (
    is            => 'rw',
    isa           => 'Maybe[Venn::Schema::Result::AssignmentGroup]',
    clearer       => 'clear_assignmentgroup',
    documentation => 'Assignment Group object',
);

has 'commit_group_id' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Identifier for the commit group',
);

=head1 METHODS

=head2 BUILD()

Initializes request and definition so they may be serialized.

=cut

sub BUILD {
    my ($self) = @_;

    # bypass ro
    $self->{request} = $self->strategy->request;
    $self->{definition} = $self->strategy->definition;

    return;
}


=head2 _finalize_placement()

Triggered when placement_rs is set.
Sets the placement_candidates (and indirectly the placement_location), placement_message, and state.
Optionally it will call postprocess_helpers when they are defined.

=cut

sub _finalize_placement { ## no critic (Subroutines::RequireFinalReturn)
    my ($self) = @_;

    $self->log->tracef("Finalizing placement");

    try {
        ## no critic (RequireInitializationForLocalVars)
        # temporarily turn off errors because of suboptimal query warning
        local $self->schema->storage->dbh->{RaiseError} if $self->schema->storage_type =~ /db2/i;
        local $self->schema->storage->dbh->{HandleError} if $self->schema->storage_type =~ /db2/i;
        ## use critic (RequireInitializationForLocalVars)

        # This is *actually* where the placement query is executed
        $self->placement_candidates([ $self->placement_rs->as_hash->all ]);
    }
    catch ($err) {
        $self->log->warnf("Error finalizing placement: %s", $err);
        $self->state('NotPlaced');
        $self->error($err);
    }

    if ($self->error) {
        $self->generate_placement_message();
    }
    else {
        try {
            if ($self->placement_location) {
                $self->log->debug("Placement succeeded");
                $self->state('Placed');
                unless ($self->strategy->simulate) {
                    $self->_run_preprocessing();
                    $self->generate_assignmentgroup_and_assignments();
                    $self->_run_postprocessing();
                }
            }
            else {
                $self->log->debug("No capacity for placement");
                $self->state('NoCapacity');
                $self->error('No capacity');
            }
        }
        catch ($err) {
            $self->log->warnf("Error finalizing placement: %s", $err);
            $self->state('NotPlaced');
            $self->error($err);
        }
    }

    return;
}

=head2 _run_preprocessing()

Run all preprocess_helpers which are set in AGT definition.
Preprocessing allows the allocator to bail out if no capacity available.

eg.:
        preprocess_helpers => [
            {
                MyHelper => [qw/ my_method /],
            }

It will call my_method() from package Venn::PlacementEngine::Helpers::MyHelper.

=cut

sub _run_preprocessing {
    my ($self) = @_;

    # Run optional pre-processing from definition
    my $preprocess_helpers = $self->definition->{preprocess_helpers} // [];
    for my $helperhash (@$preprocess_helpers) {
        for my $helper (keys %$helperhash) {
            my $role = "Venn::PlacementEngine::Helper::$helper";
            ensure_all_roles($self, $role); # dynamically apply the helper role
            for my $method (@{ $helperhash->{$helper} }) {
                $self->$method;
            }
        }
    }

    return;
}

=head2 _run_postprocessing()

Run all postprocess_helpers which are set in AGT definition.
Currently it is used by port allocation mechanism to finalize allocation.
eg.:
        postprocess_helpers => [
            {
                MyHelper => [qw/ finalize /],
            }

It will call finalize() from package Venn::PlacementEngine::Helpers::MyHelper.

=cut

sub _run_postprocessing {
    my ($self) = @_;

    # Run optional post-processing from definition
    my $postprocess_helpers = $self->definition->{postprocess_helpers} // [];
    for my $helperhash (@$postprocess_helpers) {
        for my $helper (keys %$helperhash) {
            my $role = "Venn::PlacementEngine::Helper::$helper";
            ensure_all_roles($self, $role); # dynamically apply the helper role
            for my $method (@{ $helperhash->{$helper} }) {
                $self->$method;
            }
        }
    }

    return;
}

=head2 _run_resultprocessing()

Run all result_helpers which are set in AGT definition.
Currently it is used by port allocation mechanism to add ports after multi-allocation.
eg.:
        result_helpers => [
            {
                MyHelper => [qw/ postallocate /],
            }

It will receive the to-be-returned result as a parameter.

=cut

sub _run_resultprocessing { ## no critic Subroutines::ProhibitUnusedPrivateSubroutines
    my ($self, @params) = @_;

    # Run optional result processing from definition
    my $result_helpers = $self->definition->{result_helpers} // [];
    for my $helperhash (@$result_helpers) {
        for my $helper (keys %$helperhash) {
            my $role = "Venn::PlacementEngine::Helper::$helper";
            ensure_all_roles($self, $role); # dynamically apply the helper role
            for my $method (@{ $helperhash->{$helper} }) {
                $self->$method(@params);
            }
        }
    }

    return;
}

=head2 _set_placement_location()

Triggered when placement_candidates is set.
Sets the placement_location to the first (best) placement candidate.

=cut

sub _set_placement_location {
    my ($self) = @_;

    $self->placement_location($self->placement_candidates->[0]) if defined $self->placement_candidates->[0];

    return;
}

=head2 parse_placement_location()

Parses the placement_location hash which looks roughly like this:
    {
        memory_provider_id => 10,
        memory_avg         => 13.333,
        memory_total       => 400,
        cpu_provider_id => 15,
        ... etc,
    }

and returns a new hash like this:
    {
        memory => 10,
        cpu => 15,
    }

=cut

sub parse_placement_location {
    my ($self) = @_;

    my %parsed_info;

    my @relevant_keys = grep { /_provider_id$/ } keys %{ $self->placement_location };
    for my $relevant_key (@relevant_keys) {
        ( my $new_key = $relevant_key ) =~ s/_provider_id$//;
        $parsed_info{$new_key} = $self->placement_location->{$relevant_key};
    }

    return \%parsed_info;
}


=head2 generate_placement_message()

Generates the placement message using the place_format and place_args
in the AGTs definition.

Example AGT definition:
    place_format => 'host %s, disk %s',
    place_args   => [qw( memory.host_name disk.disk_name )],

=cut

sub generate_placement_message {
    my ($self) = @_;

    # A message is already set
    return if defined $self->placement_message;

    my $msg;
    if (defined $self->placement_location && $self->state eq 'Placed' && defined $self->definition->{place_args}) {
        try {
            ## no critic (ProhibitComplexMappings)
            # convert memory.hsot_name to memory_host_name to match placement_location fields
            my @sprintf_args = map { ( my $field = $_ ) =~ s/\./_/; $self->placement_location->{$field} } @{ $self->definition->{place_args} };
            ## use critic (ProhibitComplexMappings)
            # place_format => 'cluster %s, share %s, filer %s',
            # place_args   => [qw( memory.cluster_name nas.share_name nas.filer_name )],
            if (scalar @sprintf_args == scalar @{ $self->definition->{place_args} }) {
                $msg = sprintf($self->definition->{place_format}, @sprintf_args)
            }
            else {
                # TODO: exception?
                die sprintf(
                    "Not enough args:\nsprintf_args: %s\ndefinition args:%s",
                    join(', ', @sprintf_args),
                    join(', ', @{ $self->definition->{place_args} }),
                );
            }
        }
        catch ($err) {
            $self->placement_message("Error generating placement message: $err");
            return;
        }
    }
    else {
        given ($self->state) {
            when (/^Pending$/) { $msg = "Pending placement"; }
            when (/^NotPlaced$/) { $msg = "Unable to place"; }
            when (/^NoCapacity$/) { $msg = "No capacity"; }
            # TODO: this should probably throw some kind of exception?
            default { $msg = "Unknown error occurred during placement"; }
        }
    }
    $self->placement_message($msg);

    return;
}


=head2 generate_assignmentgroup_and_assignments()

Generates a new AssignmentGroup based on the placement location in the result.

Steps:
    Wrapped in a transaction:
        Create the AssignmentGroup
        Parse the placement result\'s placement_location (hashref of resource => amount)
        Create Assignments for each

=cut

sub generate_assignmentgroup_and_assignments {
    my ($self) = @_;

    $self->log->debugf("Creating AssignmentGroup and Assignments");
    try {
        $self->schema->storage->dbh_do(sub {
            my %parsed_info = %{ $self->parse_placement_location() };

            # Assignment group
            $self->assignmentgroup($self->create_or_update_assignmentgroup());

            # Commit group identifier
            if (not defined $self->strategy->commit_group_id) {
                $self->commit_group_id($self->generate_uuid());
            }
            else {
                $self->commit_group_id($self->strategy->commit_group_id);
            }
            for my $providertype (keys %parsed_info) {
                my $provider_id = $parsed_info{$providertype};
                my $provider_class = $self->schema->provider_mapping->{$providertype}->{source};
                if ( $self->schema->resultset($provider_class)->result_class->named_resources ) {
                    $self->create_named_assignment($providertype, $provider_id, $self->commit_group_id);
                }
                else {
                    $self->create_assignment($providertype, $provider_id, $self->commit_group_id);
                }
            }
            if (%{$self->placement_named_resources}) {
                $self->assignmentgroup($self->create_or_update_assignmentgroup());
            }
        });
    }
    catch ($err) {
        $self->log->error("Error creating Assignment Group: $err");
        $self->placement_message("Error creating Assignment Group: $err");
        $self->state('NotPlaced');
        $self->clear_assignmentgroup();
    }

    return;
}

=head2 create_or_update_assignmentgroup()

Creates a new AssignmentGroup. If an AssignmentGroup already exists, (in the
case of Migrate, for example), then retrieve it.

    return : (AssignmentGroup) The newly created AssignmentGroup object

=cut

sub create_or_update_assignmentgroup {
    my ($self) = @_;

    my $ag;
    if ( (not defined $self->strategy->assignment_group) && (not defined $self->assignmentgroup )) {
        my $identifier = $self->request->identifier // $self->generate_uuid();
        $self->log->debugf("Creating a new AssignmentGroup: friendly %s, identifier %s",
            $self->request->friendly, $identifier);

        $ag = $self->schema->resultset('AssignmentGroup')->create({
            assignmentgroup_type_name => $self->request->assignmentgroup_type,
            # TODO: add this to the request
            friendly    => $self->request->friendly,
            identifier  => $identifier,
            metadata    => {
                placement => {
                    location  => $self->placement_location,
                    info      => $self->placement_info,
                },
                request => {
                    attributes => $self->request->attributes,
                    location => $self->request->location,
                },
            },
        });
    }
    else {
        my $identifier = $self->assignmentgroup ? $self->assignmentgroup->identifier : $self->strategy->assignment_group;
        $self->log->debugf("Updating an existing AssignmentGroup: identifier: %s", $identifier);

        $ag = $self->assignmentgroup || $self->schema->resultset('AssignmentGroup')
            ->find_by_identifier($self->strategy->assignment_group);

        if ($ag) {
            # Update metadata with new placement and merge custom_data too
            $ag->update({
                metadata => {
                    placement => {
                        location => $self->placement_location,
                        info     => $self->placement_info,
                        named_resources => $self->placement_named_resources,
                    },
                    request => {
                        attributes => $self->request->attributes,
                        location => $self->request->location,
                    },
                    custom_data => $ag->metadata->{custom_data},
                },
            });
        }
        else {
            Venn::Exception::Placment::InvalidAssignmentGroup->throw({
                assignment_group => $self->strategy->assignment_group
            });
        }
    }

    return $ag;
}


=head2 create_assignment($providertype, $provider_id)

Creates a new Assignment for a provider (via its ID) having a specific providertype.

    param $providertype    : (Str) Provider type (e.g. memory, nas, etc.)
    param $provider_id     : (Int) ID of the provider
    param $commit_group_id : (Str) Commit Group ID
    return                 : (Assignment) The newly created assignment object

=cut

sub create_assignment {
    my ($self, $providertype, $provider_id, $commit_group_id) = @_;

    $self->log->debugf(
        "Creating an assignment of size %s for provider ID %s, ag ID %s, cg ID %s",
        $self->request->resources->{$providertype},
        $provider_id, $self->assignmentgroup->assignmentgroup_id,
        $commit_group_id,
    );
    # TODO: create_related instead?
    my $a = $self->schema->resultset('Assignment')->create({
        provider_id        => $provider_id,
        assignmentgroup_id => $self->assignmentgroup->assignmentgroup_id,
        size               => $self->request->resources->{$providertype},
        committed          => $self->request->commit,
        commit_group_id    => $commit_group_id,
    });

    return $a;
}

=head2 create_named_assignment($providertype, $provider_id)

Creates named assignments ( x provided size ) for a provider (via its ID) having a specific providertype.

    param $providertype    : (Str) Provider type (e.g. memory, nas, etc.)
    param $provider_id     : (Int) ID of the provider
    param $commit_group_id : (Str) Commit Group ID
    return                 : (ArrayRef[Assignment]) The newly created assignment objects in an arrayref

=cut

sub create_named_assignment {
    my ($self, $providertype, $provider_id, $commit_group_id) = @_;

    my $provider_class = $self->schema->provider_mapping->{$providertype}->{source};
    my $rs = $self->schema->resultset($provider_class)->search({'me.provider_id' => $provider_id})->with_unassigned_resources();
    my $resourcename = $self->schema->resultset($provider_class)->result_class->named_resources_resourcename;

    my (@a, @resourcenames);

    for ( 1 .. $self->request->resources->{$providertype} ) {
        my $row = $rs->next();
        my $resource_id = $row->get_column('resource_id');
        $self->log->debugf(
            "Creating an assignment of resource ID %s for provider ID %s, ag ID %s, cg ID %s",
            $resource_id, $provider_id, $self->assignmentgroup->assignmentgroup_id, $commit_group_id,
        );
        # TODO: create_related instead?
        push @a, $self->schema->resultset('Assignment')->create({
            provider_id        => $provider_id,
            assignmentgroup_id => $self->assignmentgroup->assignmentgroup_id,
            size               => 1,
            committed          => $self->request->commit,
            commit_group_id    => $commit_group_id,
            resource_id        => $resource_id,
        });
        push @resourcenames, { $resourcename => $row->get_column($resourcename) };
    }
    $self->placement_named_resources->{$providertype} = \@resourcenames;

    return \@a;
}


__PACKAGE__->meta->make_immutable();
