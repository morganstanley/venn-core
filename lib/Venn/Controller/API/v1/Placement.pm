package Venn::Controller::API::v1::Placement;

=head1 NAME

Venn::Controller::API::v1::Placement

=head1 DESCRIPTION

Placement algorithm interface.

Attempts to find placement for a set of resources.  Creates an Assignment Group
if it's able to and allocates assignments appropriately.

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
use namespace::autoclean;

use TryCatch;
use YAML::XS;

use Venn::Types;
use Venn::PlacementEngine;
use Data::UUID;

BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

class_has 'uuid_generator' => (
    is      => 'ro',
    isa     => 'Data::UUID',
    default => sub { return Data::UUID->new() },
    documentation => 'UUID generator for commit_group_id',
);

=head1 METHODS

=head2 post_place

REST POST /place/$assignmentgroup_type/$strategy    <placement>
    Places a request and generates an Assignment Group using the PlacementEngine.

    Expected data:
    ---
    resources:
        esxram: 4
        esxcpu: 1000
        filerio: 20
        nas: 60
    attributes:
        environment: dev
        capabilities:
            - dev
        owner: 12345
    location:
        continent: na
        building: zy
    friendly: evmx123

    param $assignmentgroup_type : (String) assignment group type (placement resources) [required]
    param $strategy             : (String) placement strategy name [required]
    body                        : (PlacementRequest) specification of the requested resources [required]
    response 201                : Placed
    response 202                : Pending placement (queued up)
    response 409                : Unable to place

=cut

sub post_place :POST Path('place') Args(2) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $assignmentgroup_type, $strategy) = @_;

    return $self->_perform_placement($c, $assignmentgroup_type, $strategy);
}

=head2 post_simulate_place

REST POST /simulate_place/$assignmentgroup_type/$strategy    <placement>
    Simulates placement (does not create an Assignment Group)

    param $assignmentgroup_type : (String) assignment group type (placement resources) [required]
    param $strategy             : (String) placement strategy name [required]
    body                        : (PlacementRequest) specification of the requested resources [required]
    response 201                : Placed
    response 202                : Pending placement (queued up)
    response 409                : Unable to place

=cut

sub post_simulate_place :POST Path('simulate_place') Args(2) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $assignmentgroup_type, $strategy) = @_;

    return $self->_perform_placement($c, $assignmentgroup_type, $strategy, {
        simulate => 1,
    });
}

=head2 unassign_POST

REST POST /unassign/$uuid    <placement>
    Unassigns resources associated with an identifier.

    param $uuid  : (String) assignment group identifier [required]
    response 200 : unassigned resources
    response 404 : assignment group not found
    response 500 : error unassigning resources

=cut

sub unassign_POST :POST Path('unassign') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $identifier) = @_;
    my $unassign_args = $c->req->data;

    try {
        my $ag = $c->model('VennDB::AssignmentGroup')
            ->find_by_identifier($identifier);
        if ($ag) {
            my $result = $ag->unassign($unassign_args);

            return $self->simple_ok($c, {
                commit_group_id => $result->{commit_group_id},
                message         => "Assignments zeroed for $identifier",
            });
        }
        else {
            return $self->simple_not_found($c, "Assignment Group (identifier: %s) not found", $identifier);
        }
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }
}

=head2 post_resize

REST POST /resize/$uuid    <placement>
    Resize assignments for an assignmentgroup with given resources

    Expected data: { memory: 4, cpu: 1000, io: 20, disk: 60 }

    param $uuid  : (String) assignment group identifier [required]
    body         : (ResizeRequest) resource specification [required]
    response 200 : Resized
    response 500 : Error resizing

    schema ResizeRequest: {
      "properties": {
        "memory": { "type": "integer", "description": "example memory value", "example": 512 },
        "cpu": { "type": "integer", "description": "example cpu value", "example": 2000 },
        "io": { "type": "integer", "description": "example io value", "example": 100 },
        "disk": { "type": "integer", "description": "example disk value", "example": 600 }
      }
    }

=cut

sub post_resize :POST Path('resize') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $identifier) = @_;
    my $resources = $c->req->data;

    try {
        my $result = $c->model('VennDB::AssignmentGroup')
            ->find_by_identifier($identifier)
            ->resize($resources);

        return $self->simple_ok($c, {
            commit_group_id => $result->{commit_group_id},
            message => "Assignments adjusted for resize for $identifier",
        });
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }
}

=head2 post_migrate_specific

REST POST /migrate_specific/$uuid    <placement>
    Reassign assignments to given providers
    If a provider for a resource is not specified, the assignment for that
    resource will not be changed

    Optional data: { manual_placement: { cpu: myhost } }

    param $uuid  : (String) assignment group identifier [required]
    body         : (MigrateRequest) define provider targets
    response 201 : Migrated
    response 202 : Pending placement (queued up)
    response 409 : Unable to migrate

    schema MigrateRequest: {
      "properties": {
        "manual_placement": { "$ref": "#/definitions/MigrateRequestTargets", "description": "targets for different providers" }
      }
    }

    schema MigrateRequestTargets: {
      "properties": {
        "cpu": { "type": "string", "description": "target specification for cpu", "example": "myhost" }
      }
    }

=cut

sub post_migrate_specific :POST Path('migrate_specific') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $identifier) = @_;

    return $self->_perform_migrate($c, $identifier);
}

=head2 post_simulate_migrate_specific

REST POST /simulate_migrate_specific/$uuid    <placement>
    Simulates migrate_specific (does not create an Assignment Group)

    param $uuid  : (String) assignment group identifier [required]
    body         : (MigrateRequest) define provider targets
    response 201 : Simulated migrate
    response 202 : Pending placement (queued up)
    response 409 : Unable to migrate

=cut

sub post_simulate_migrate_specific :POST Path('simulate_migrate_specific') Args(1) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $identifier) = @_;

    return $self->_perform_migrate($c, $identifier, {
        simulate => 1,
    });
}

=head2 post_migrate_place

REST POST /migrate_place/$uuid    <placement>
    Reassign assignments to given providers
    If a provider for a resource is not specified, a placement will be
    attempted for that resource and the assignments may change.

    Optional data: { manual_placement: { cpu: myhost } }

    param $uuid  : (String) assignment group identifier [required]
    body         : (MigrateRequest) define provider targets
    response 201 : Migrated
    response 202 : Pending placement (queued up)
    response 409 : Unable to migrate

=cut

sub post_migrate_place :POST Path('migrate_place') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $identifier) = @_;

    return $self->_perform_migrate($c, $identifier, {
        place => 1,
    });
}

=head2 post_simulate_migrate_place

REST POST /simulate_migrate_place/$uuid    <placement>
    Simulates migrate_place (does not create an Assignment Group)

    param $uuid  : (String) assignment group identifier [required]
    body         : (MigrateRequest) define provider targets
    response 201 : Migrated
    response 202 : Pending placement (queued up)
    response 409 : Unable to migrate

=cut

sub post_simulate_migrate_place :POST Path('simulate_migrate_place') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $identifier) = @_;

    return $self->_perform_migrate($c, $identifier, {
        place => 1,
        simulate => 1,
    });
}

=head2 _perform_migrate($c, $identifier, \%params)

Performs a placement/assignment given the params passed in.

    param  $identifier : (String) assignment group identifier
    param \%params     : (HashRef) migrate parameters

=cut

sub _perform_migrate :Private {
    my ($self, $c, $identifier, $params) =  @_;

    my $data = $c->req->data;
    my $schema = $c->model('VennDB')->schema;

    $params->{simulate} //= 0;
    $params->{place} //= 0;

    try {
        my $commit_group_id = $self->uuid_generator->create_str();
        $schema->txn_do(sub {
            my $assignmentgroup = $schema->resultset('AssignmentGroup')->find_by_identifier($identifier);
            my $assignments_rs = $schema->resultset('Assignment')->group_by_assignmentgroup_id($assignmentgroup->assignmentgroup_id);

            # Build placement hash for the PE
            my %placement;
            $placement{assignmentgroup_type} = $assignmentgroup->assignmentgroup_type_name;

            # 1) migrate_place: override defaults entirely with request
            # 2) migrate_specific: only override specified attributes, but conserve others
            if ($params->{place} && defined $data->{attributes}) {
                $placement{attributes} = $data->{attributes};
            }
            elsif (defined $data->{attributes}) {
                foreach my $res (keys %{$data->{attributes}}) {
                    $placement{attributes}->{$res} = $data->{attributes}->{$res};
                }
            }

            if ($params->{place} && defined $data->{location}) {
                $placement{location} = $data->{location};
            }
            elsif (defined $data->{location}) {
                foreach my $param (keys %{$data->{location}}) {
                    $placement{location}->{$param} = $data->{location}->{$param};
                }
            }

            while (my $assignment = $assignments_rs->next) {
                my $resname = $assignment->get_column('providertype_name');
                my $provider_class = $schema->provider_mapping->{$resname}->{source};
                my $provider_rs = $schema->resultset($provider_class);
                my $primary_field = $provider_rs->result_class->primary_field();

                # Find current provider
                my $current_provider = $provider_rs->find($assignment->get_column('provider_id'));

                if (defined $data->{manual_placement}->{$resname} || $params->{place}) {
                    # Negate current assignment
                    $c->log->debug('Migrate: negate assignment for provider: ' . $current_provider->provider_id);
                    if (not $params->{simulate}) {
                        $schema->resultset('Assignment')->create({
                            provider_id => $current_provider->provider_id,
                            assignmentgroup_id => $assignmentgroup->assignmentgroup_id,
                            size => $assignment->get_column('total') * -1,
                            committed => 0,
                            commit_group_id => $commit_group_id,
                        });
                    }

                    # Add resource to placement
                    $placement{resources}->{$resname} = $assignment->get_column('total');

                    # Add to manual placement if resource was specified
                    $placement{manual_placement}->{$resname} = $data->{manual_placement}->{$resname}
                        if defined $data->{manual_placement}->{$resname};
                }
                else {
                    # Add to manual placement with 0 assigned resources for current provider
                    $placement{manual_placement}->{$resname} = $current_provider->get_column($primary_field);
                    $placement{resources}->{$resname} = 0;
                }
            }

            # Perform placement with built placement hash
            $c->req->data(\%placement);
            return $self->_perform_placement(
                $c, $assignmentgroup->assignmentgroup_type_name, 'biggest_outlier',
                {
                    simulate => $params->{simulate},
                    assignment_group => $identifier,
                    commit_group_id => $commit_group_id,
                }
            );
        });
    }
    catch ($err) {
        $c->log->error($err);
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }
}

=head2 _perform_placement($c, \%params)

Performs a placement/assignment given the params passed in.

    param $assignmentgroup_type : (String) assignment group type (placement resources)
    param $strategy             : (String) placement strategy name

=cut

sub _perform_placement :Private {
    my ($self, $c, $assignmentgroup_type, $strategy, $params) = @_;

    $c->log->debug("Performing placement: of type $assignmentgroup_type with strategy $strategy");

    $params->{schema}   //= $c->model('VennDB')->schema;
    $params->{simulate} //= 0;
    $params->{all_rows} //= $c->req->param('all_rows') // 0;

    my @placement_result;
    try {
        my $pengine = Venn::PlacementEngine->create($strategy, $assignmentgroup_type, $c->request->data, $params);

        @placement_result = $pengine->place();
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, $err->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }

    given ($placement_result[0]->state) {
        when (/^Placed$/) {
            return $self->status_created($c, {
                location => $self->_ag2uri($c, $placement_result[0]->assignmentgroup, $params->{simulate}),
                entity   => @placement_result == 1 ? $placement_result[0] : \@placement_result,
            });
        }
        when (/^(?:NotPlaced|NoCapacity)$/) {
            # Rollback required in the case of migration
            $c->model('VennDB')->schema->txn_rollback if defined $params->{commit_group_id};
            return $self->simple_conflict($c, $placement_result[0]->error);
        }
        when (/^Pending$/) {
            return $self->status_accepted($c, {
                entity => {
                    status  => 'pending',
                    message => 'Placement has been queued up',
                },
            });
        }
    }
}

=item _ag2uri

Takes an assignment group and returns its URI.

    param $c                : (Catalyst) Catalyst context
    param $assignment_group : (AssignmentGroup Result) assignment group result object
    param $simulate         : (Bool) was the placement simulated?
    return                  : (String) URI

=cut

sub _ag2uri :Private {
    my ($self, $c, $assignment_group, $simulate) = @_;

    if ($simulate) {
        return "";
    }
    else {
        return "/api/v1/assignmentgroup/" . $assignment_group->identifier;
    }
}

__PACKAGE__->meta->make_immutable;
