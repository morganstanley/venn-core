package Venn::SchemaRole::Result::AssignmentGroup;

=head1 NAME

Venn::SchemaRole::Result::AssignmentGroup

=head1 DESCRIPTION

Assignment Group methods.

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
use MooseX::ClassAttribute;

use Venn::PlacementEngine;

class_has 'uuid_generator' => (
    is      => 'ro',
    isa     => 'Data::UUID',
    default => sub { return Data::UUID->new() },
    documentation => 'UUID generator for commit_group_id',
);

=head1 METHODS

=head2 around TO_JSON()

Wraps TO_JSON() to add all of the assignments related to the Assignment Group.

TODO: add a flag to make this explicit

=cut

around 'TO_JSON' => sub {
    my $orig = shift;
    my $self = shift;

    my $hash = $self->$orig(@_);

    $hash->{assignments} = [ map { $_->TO_JSON() } $self->assignments->all ];

    return $hash;
};

=head2 unassign()

Deduct assignments for the assignment group

    param \%unassign_args : (HashRef) Takes a 'commit' option that indicates that the unassignment
                            should be immediately commited if true, or not if false.
    return                : (HashRef) Result

=cut

sub unassign {
    my ($self, $unassign_args) = @_;
    my $schema = $self->result_source->schema;

    my $commit_group_id = $self->uuid_generator->create_str();
    $schema->txn_do(sub {
        # Lock the assignments table
        $schema->resultset('Assignment')->lock_table();

        # Zeroize sum of assignments for each provider
        $self->log->debugf("Zeroizing assignments for assignmentgroup: %s", $self->assignmentgroup_id);

        my $assignments_rs = $schema->resultset('Assignment')->group_by_assignmentgroup_id($self->assignmentgroup_id);
        while (my $assignment = $assignments_rs->next) {
            my $provider_map = Venn::Schema->provider_mapping->{ $assignment->get_column('providertype_name') };
            if (%$provider_map) {
                my $rs = $schema->resultset($provider_map->{source});
                if (blessed $rs && $rs->can('custom_unassign')) {
                    my $skip_unassign = $rs->custom_unassign($assignment, $unassign_args);
                    next if $skip_unassign; # does the custom unassign want to allow regular unassignment?
                }
            }

            $self->log->debugf("Zeroizing ag %s, assignment %s of type %s having %s",
                $self->assignmentgroup_id, $assignment->provider_id, $assignment->get_column('providertype_name'),
                $assignment->get_column('total'));

            if ($assignment->get_column('total') > 0) {
                # Insert negative assignment to zeroize provider assignment
                my $committed = time();
                if (defined $unassign_args->{commit} && $unassign_args->{commit} == 0) {
                    $committed = 0;
                }
                $self->_create_negative_assignment($assignment, $committed, $commit_group_id);
            }
        }
        $self->log->debugf("Done unassigning");
    });

    return { commit_group_id => $commit_group_id };
}

=head2 _create_negative_assignment($assignment, $committed, $commit_group_id)

Creates a negative assignment to match the given assignment.

    param $assignment      : (Assignment) Assignment result
    param $committed       : (Int) Committed time or 0
    param $commit_group_id : (UUID) Commit Group ID
    return                 : Created assignment

=cut

sub _create_negative_assignment {
    my ($self, $assignment, $committed, $commit_group_id) = @_;

    return $self->result_source->schema->resultset('Assignment')->create({
        provider_id        => $assignment->provider_id,
        assignmentgroup_id => $self->assignmentgroup_id,
        size               => $assignment->get_column('total') * -1,
        committed          => $committed,
        commit_group_id    => $commit_group_id,
        resource_id        => $assignment->resource_id,
     });
}

=head2 resize($resources)

Resize assignments for specified providers

    param \%resources : (HashRef) Placement options. Example:
                          {
                            nas => 120,
                            esxcpu => 4,
                          }
    return            : (HashRef) Result

=cut

sub resize {
    my ($self, $resources) = @_;
    my $schema = $self->result_source->schema;

    my $commit_group_id = $self->uuid_generator->create_str();
    $schema->txn_do(sub {
        # Lock the assignments table
        $schema->resultset('Assignment')->lock_table();

        # Retrieve all assignments for the assignment group
        my $assignments_rs = $schema->resultset('Assignment')
            ->group_by_assignmentgroup_id($self->assignmentgroup_id);

        # Adjust assignments for each provider for resizing
        $self->log->debug("Adjusting assignments for assignmentgroup: " . $self->assignmentgroup_id);
        while (my $assignment = $assignments_rs->next) {
            next if not defined $resources->{$assignment->get_column('providertype_name')};
            my $resize_amount =
                 $resources->{$assignment->get_column('providertype_name')} - $assignment->get_column('total');

            if ($resize_amount != 0) {
                $schema->resultset('Assignment')->create({
                    provider_id => $assignment->provider_id,
                    assignmentgroup_id => $self->assignmentgroup_id,
                    size => $resize_amount,
                    committed => 0,
                    commit_group_id => $commit_group_id,
                 });
            }
        }
    });

    return { commit_group_id => $commit_group_id };
}

=head2 resize_capacity($assignmentgroup_type, $resources)

Compute resize capacity for the assignment group given placement options

    param $assignmentgroup_type : (Str) Assignment Group Type
    param $resources            : (HashRef) Placement options. Examples:
                                            {
                                                nas => 120,
                                                esxcpu => 4,
                                            }
    return                      : (Int) Whether there is capacity or not

=cut

sub resize_capacity {
    my ($self, $assignmentgroup_type, $placement) = @_;
    my $schema = $self->result_source->schema;

    my $assignments_rs = $schema->resultset('Assignment')
        ->group_by_assignmentgroup_id($self->assignmentgroup_id);

    # resize shouldn't care about location
    $placement->{location} = {};

    # resize shouldn't care about attributes
    $placement->{attributes} = {};

    # ignore capabilities
    $placement->{force_placement} = 1;

    # Compute the difference
    while (my $assignment = $assignments_rs->next) {
        my $provider_type = $assignment->get_column('providertype_name');

        next if not defined $placement->{resources}->{$provider_type};
        next if $assignment->get_column('total') == 0;

        my $size = $assignment->get_column('total');
        my $difference = $placement->{resources}->{$provider_type} - $size;

        if ($difference <= 0) {
            delete $placement->{resources}->{$provider_type};
            next;
        }

        # Find the provider names for manual placement
        my $provider_class = $schema->provider_mapping->{$provider_type}->{source};
        my $provider_rs = $schema->resultset($provider_class);
        my $primary_field = $provider_rs->result_class->primary_field();

        my $provider = $provider_rs->find($assignment->get_column('provider_id'));

        $placement->{manual_placement}->{$provider_type} = $provider->get_column($primary_field);

        # Override resource with the difference
        $placement->{resources}->{$provider_type} = $difference;
    }

    # No resources in placement (e.g: downwards resize)
    if (scalar(keys %{$placement->{resources}}) == 0) {
        return 1;
    }
    # Compute capacity search on the differences
    else {
        my $capacity = Venn::PlacementEngine->create('capacity', $assignmentgroup_type, $placement, {
            schema => $schema,
        });
        my $summary = $capacity->capacity($placement);

        return $summary->{capacity} > 0 ? 1 : 0;
    }
}

=head2 update_metadata($data)

update metadata in a custom_data field. Previous metadata is conserved

    param $data : (HashRef) Data to update in metadata custom_data. Example:
                    {
                        hostname => izvm2504.devin3.ms.com,
                    }
    return      : (void)

=cut

sub update_metadata {
    my ($self, $data) =  @_;
    my $schema = $self->result_source->schema;

    $schema->txn_do(sub {
        my $metadata = $self->metadata || {};

        foreach my $param (keys %$data) {
            $metadata->{custom_data}->{$param} = $data->{$param};
        }

        $self->update( { metadata => $metadata } );
    });

    return;
}

1;
