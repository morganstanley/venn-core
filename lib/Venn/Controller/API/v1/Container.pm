package Venn::Controller::API::v1::Container;

=head1 NAME

Venn::Controller::API::v1::Container - Container CRUD

=head1 DESCRIPTION

RESTful interface for containers in Venn.

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
BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

use TryCatch;
use Data::Dumper;
use Venn::Types qw(:all);

## no critic (RequireFinalReturn)

=head1 METHODS

=head2 container_base

Container base.

=cut

sub container_base :Chained('/') PathPart('api/v1/container') CaptureArgs(0) { }

=head2 container_type

Captures container type into the stash

    Stashes:
    container_type: the container type
    source: the C_* class for the container
    primary_field: the primary field of the table
    display_name: display name for the container
    container_rs: container resultset

=cut

sub container_type :Chained('container_base') PathPart('') CaptureArgs(1) {
    my ($self, $c, $type) = @_;

    my %map = %{Venn::Schema::container_mapping->{$type} || {}};
    unless (%map) {
        $self->simple_not_found($c, "Container type $type not found") unless %map;
        $c->detach();
    }

    $c->stash->{container_type} = $type;
    $c->stash->{source}         = $map{source};
    $c->stash->{primary_field}  = $map{primary_field};
    $c->stash->{display_name}   = $map{display_name};
    $c->stash->{container_rs}   = $c->model('VennDB::' . $map{source});
}

=head2 container_known_pk

Captures the known container (its primary_field_value).

    Stashes:
    primary_field_value: primary field (e.g. the actual cluster_name, dzecl123)

=cut

sub container_known_pk :Chained('container_type') PathPart('') CaptureArgs(1) {
    my ($self, $c, $pk) = @_;
    $c->stash->{primary_field_value} = $pk;
}

=head2 get_all_types

REST GET /container
    GET all containers

    response 200 : (Array[Container]) list of types of containers

    schema Container: {
      "required": ["api_name", "columns", "primary_field", "class", "display_name"],
      "properties": {
        "api_name":      { "type": "string", "description": "name of container", "example": "host" },
        "columns":       { "$ref": "#/definitions/ContainerColumn", "description": "data columns example" },
        "primary_field": { "type": "string", "description": "primary key column", "example": "hostname" },
        "class":         { "type": "string", "description": "internal database table class", "example": "C_Host" },
        "display_name":  { "type": "string", "description": "display name for UI", "example": "Hosts" }
      }
    }

    schema ContainerColumn: {
      "properties": {
        "hostname": { "$ref": "#/definitions/ContainerColumnHostname" },
        "rack_name": { "$ref": "#/definitions/ContainerColumnRackname" }
      }
    }

    schema ContainerColumnHostname: {
      "properties": {
        "data_type": { "type": "string", "description": "database data type", "example": "varchar" },
        "is_foreign_key": { "type": "boolean", "description": "is it a foreign key", "example": "1" },
        "is_nullable": { "type": "boolean", "description": "could it be null value", "example": "0" },
        "display_name": { "type": "string", "description": "display name for UI", "example": "Host" },
        "validate_error": { "type": "string", "description": "error message for failed validation", "example": "Host does not exist" },
        "validate": { "type": "string", "description": "validator function reference", "example": "CODE" },
        "size": { "type": "string", "description": "database data type size", "example": 64 }
      }
    }

    schema ContainerColumnRackname: {
      "properties": {
        "data_type": { "type": "string", "description": "database data type", "example": "varchar" },
        "is_foreign_key": { "type": "boolean", "description": "is it a foreign key", "example": "1" },
        "is_nullable": { "type": "boolean", "description": "could it be null value", "example": "0" },
        "display_name": { "type": "string", "description": "display name for UI", "example": "Rack" },
        "validate_error": { "type": "string", "description": "error message for failed validation", "example": "Rack does not exist" },
        "validate": { "type": "string", "description": "validator function reference", "example": "CODE" },
        "size": { "type": "string", "description": "database data type size", "example": 64 }
      }
    }

=cut

sub get_all_types :GET Chained('container_base') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        return $self->simple_ok_with_result($c, $self->serialize_types($c, 'C'));
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, $ex->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 get_all_of_type

REST GET /container/$type
    GET all containers of a type

    param $type  : (Str) [required] type of container
    response 200 : (Array[Container]) list of containers of type $type

=cut

sub get_all_of_type :GET Chained('container_type') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my @rows = $c->stash->{container_rs}->search()->as_hash->all;
        return $self->simple_ok_with_result($c, \@rows);
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error getting container data: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 get_container

REST GET /container/$type/$name
    GET an container of type $type and name $name

    param $type  : (Str) [required] type of container
    param $name  : (Str) [required] name of container
    response 200 : (Array[Container]) container of type and name

=cut

sub get_container :GET Chained('container_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my $row = $c->stash->{container_rs}->search({
            $c->stash->{primary_field} => $c->stash->{primary_field_value},
        })->as_hash->first;

        if ($row) {
            return $self->simple_ok_with_result($c, $row);
        }
        else {
            return $self->simple_not_found($c, "Container %s/%s not found", $c->stash->{container_type},
                $c->{stash}->{primary_field_value});
        }
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error getting container data: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 put_container

REST PUT /container/$type/$name
    Creates a new or updates an existing container.

    param $type  : (Str) [required] type of container
    param $name  : (Str) [required] name of container
    body         : (Container) [required] container definition
    response 201 : (Container) container created/updated

=cut

sub put_container :PUT Chained('container_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(dev-action) {
    my ($self, $c) = @_;

    $c->req->data->{$c->stash->{primary_field}} = $c->stash->{primary_field_value};

    try {
        my $container_row = $c->stash->{container_rs}->find($c->stash->{primary_field_value});
        if ($container_row) {
            # update
            $c->log->info("Update operation");
            $container_row->update($c->req->data) if %{$c->req->data};
        } else {
            # create
            $c->log->info("Create operation");
            $c->stash->{container_rs}->create($c->req->data);
        }
        my $final_result = $c->stash->{container_rs}->search($c->stash->{primary_field_value})->as_hash->first;
        return $self->simple_created($c, $final_result);
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error creating/updating container: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: " . $err);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error creating/updating container: $err");
    }
}

=head2 delete_container

REST DELETE /container/$container_type/$primary_field_value
    Deletes an container.

    param $container_type      : (String) container type
    param $primary_field_value : (String) container primary field
    response 200               : Deleted

=cut

sub delete_container :DELETE Chained('container_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(dev-action) {
    my ($self, $c) = @_;

    try {
        my $container_row = $c->stash->{container_rs}->find($c->stash->{primary_field_value});

        if ($container_row) {
            $container_row->delete();
            return $self->simple_ok_without_result($c, "%s deleted.", $c->stash->{primary_field_value});
        }
        else {
            return $self->simple_not_found($c, "%s not found.", $c->stash->{primary_field_value});
        }
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error deleting container: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: " . $err);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error deleting container: $err");
    }
}

## use critic

__PACKAGE__->meta->make_immutable;
