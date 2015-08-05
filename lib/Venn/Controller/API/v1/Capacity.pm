package Venn::Controller::API::v1::Capacity;

=head1 NAME

Venn::Controller::API::v1::Capacity

=head1 DESCRIPTION

Computes available assignment group type capacity

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

use DBIx::Class::ResultClass::HashRefInflator;
use Data::Dumper;
use TryCatch;
use YAML::XS;

use Venn::Types;
use Venn::PlacementEngine;

use Storable qw(dclone);

BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

=head1 METHODS

=head2 post_capacity

REST POST /capacity/$assignmentgroup_type
    Compute available capacity given placement options

    Expected data:
    ---
    resources:
        memory: 4
        cpu: 1000
        io: 20
        disk: 60
    attributes:
        environment: dev
        capability:
            - explicit_a
        owner: 12345
    location:
        continent: na
        building: zy
    as_of_date: [$t0, $t1, $t2, ...]    # Optional
    provider_as_of_date: 1|0              # Optional

    param $assignmentgroup_type : (Str) [required] Assignment Group Type
    body                        : (PlacementRequest) [required] Specification of the requested resources
    response 200                : (CapacityResponse) capacity summary
    response 500                : error retrieving capacity

    schema PlacementRequest: {
      "required": ["resources", "attributes"],
      "properties": {
        "resources": {
          "description": "resource attributes according to the assignment group type",
          "$ref": "#/definitions/PlacementRequestResources"
        },
        "attributes": {
          "$ref": "#/definitions/PlacementRequestAttributes"
        },
        "location": {
          "$ref": "#/definitions/PlacementRequestLocation"
        },
        "as_of_date": {
          "type": "array",
          "items": { "type": "integer", "description": "timestamp", "example": "1396807033" }
        },
        "provider_as_of_date": { "type": "boolean", "description": "1 indicates provider constraint", "example": 1 }
      }
    }

    schema PlacementRequestResources: {
      "properties": {
        "memory": { "type": "integer", "description": "example memory resource", "example": 256 },
        "cpu":    { "type": "integer", "description": "example cpu resource", "example": 1000 },
        "io":     { "type": "integer", "description": "example IO resource", "example": 20 },
        "disk":   { "type": "integer", "description": "example disk resource", "example": 60 }
      }
    }

    schema PlacementRequestAttributes: {
      "properties": {
        "environment":  { "type": "string", "description": "environment of the resources", "example": "dev" },
        "owner":        { "type": "integer", "description": "owner ID of resources", "example": 12345 },
        "capability": {
          "type": "array",
          "items": { "type": "string", "description": "capabilities/tags of resource", "example": "localdisk" }
        }
      }
    }

    schema PlacementRequestLocation: {
      "properties": {
        "continent": { "type": "string", "description": "example continent location", "example": "na" },
        "building":  { "type": "string", "description": "example building location", "example": "zy" }
      }
    }

    schema CapacityResponse: {
      "required": ["capacity"],
      "properties": {
        "capacity": { "type": "integer", "description": "maximum number of resource groups to be allocated", "example": 20 },
        "memory":   { "type": "integer", "description": "maximum number of resource groups to be allocated, memory wise", "example": 50 },
        "cpu":      { "type": "integer", "description": "maximum number of resource groups to be allocated, cpu wise", "example": 150 },
        "io":       { "type": "integer", "description": "maximum number of resource groups to be allocated, io wise", "example": 75 },
        "disk":     { "type": "integer", "description": "maximum number of resource groups to be allocated, storage wise", "example": 20 }
      }
    }

=cut

sub post_capacity :POST Path('capacity') Args(1) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $assignmentgroup_type) = @_;
    my $placement = $c->req->data;

    $c->log->debugf("Capacity request for %s: %s", $assignmentgroup_type, Dumper($placement));

    # Multiple capacity requests
    if (defined $placement->{as_of_date} and ref($placement->{as_of_date}) eq 'ARRAY') {
        my $capacity_placement = dclone($placement);
        my @summaries;
        foreach my $date (@{$placement->{as_of_date}}) {
            try {
                $capacity_placement->{as_of_date} = $date;
                my $pengine = Venn::PlacementEngine->create('capacity', $assignmentgroup_type, $capacity_placement, {
                    schema => $c->model('VennDB')->schema,
                });
                my $summary = $pengine->capacity($capacity_placement);
                $summary->{as_of_date} = $date;
                $summary->{provider_as_of_date} = $date if $placement->{provider_as_of_date};

                push @summaries, $summary;
            }
            catch ($err) {
                return $self->simple_internal_server_error($c, "Error retrieving capacity: %s", $err);
            }
        }

        return $self->simple_ok_with_result($c, \@summaries);
    }
    # Single capacity request
    else {
        try {
            my $pengine = Venn::PlacementEngine->create('capacity', $assignmentgroup_type, $placement, {
                schema => $c->model('VennDB')->schema,
            });
            my $summary = $pengine->capacity($placement);
            $summary->{as_of_date} = $placement->{as_of_date} if defined $placement->{as_of_date};

            return $self->simple_ok_with_result($c, $summary);
        }
        catch ($err) {
            return $self->simple_internal_server_error($c, "Error retrieving capacity: %s", $err);
        }
    }
}

=item post_resize_capacity

REST POST /resize_capacity/$assignmentgroup_type/$identifier    <capacity>
    Compute available capacity given placement options but restricted on the
    same provider types (e.g. cluster_name, filer_name, share_name)

    param $assignmentgroup_type : (Str) [required] Assignment Group Type
    param $identifier : (String) [required] Assignment Group identifier to be resized
    body              : (PlacementRequest) [required] Specification of the requested resources
    response 200      : (CapacityResponse) capacity exists to fulfill the resize request
    response 400      : no capacity
    response 500      : error calculating capacity

=cut

sub post_resize_capacity :POST Path('resize_capacity') Args(2) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $assignmentgroup_type, $identifier) = @_;
    my $placement = $c->req->data;
    my $schema = $c->model('VennDB')->schema;

    $c->log->debugf("Resize capacity request: %s", Dumper($placement));

    try {
        my $success = $c->model('VennDB::AssignmentGroup')
            ->find_by_identifier($identifier)
            ->resize_capacity($assignmentgroup_type, $placement);

        if ($success) {
            return $self->simple_ok_without_result($c);
        }
        else {
            # TODO: should be something else
            return $self->simple_bad_request($c, 'No capacity available');
        }
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error retrieving capacity: %s", $err);
    }
}

__PACKAGE__->meta->make_immutable;
