package Venn::Controller::API::v1::Attribute;

=head1 NAME

Venn::Controller::API::v1::Attribute - Attribute CRUD

=head1 DESCRIPTION

RESTful interface for attributes in Venn.

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

=head2 base

Attribute base.

=cut

sub base :Chained('/') PathPart('api/v1/attribute') CaptureArgs(0) { }

=head2 attribute_type

Captures attribute type into the stash

    Stashes:
    attribute_type: the attribute type
    source: the A_* class for the attribute
    primary_field: the primary field of the table
    display_name: display name for the attribute
    attribute_rs: attribute resultset

=cut

sub attribute_type :Chained('base') PathPart('') CaptureArgs(1) {
    my ($self, $c, $type) = @_;

    my %map = %{Venn::Schema::attribute_mapping->{$type} || {}};
    unless (%map) {
        $self->simple_not_found($c, "Attribute type $type not found") unless %map;
        $c->detach();
    }

    $c->stash->{attribute_type} = $type;
    $c->stash->{source}         = $map{source};
    $c->stash->{primary_field}  = $map{primary_field};
    $c->stash->{display_name}   = $map{display_name};
    $c->stash->{attribute_rs}   = $c->model('VennDB::' . $map{source});
}

=head2 attribute_known_pk

Captures the known attribute (its primary_field_value).

    Stashes:
    primary_field_value: primary field (e.g. the actual cluster_name, dzecl123)

=cut

sub attribute_known_pk :Chained('attribute_type') PathPart('') CaptureArgs(1) {
    my ($self, $c, $pk) = @_;

    $c->stash->{primary_field_value} = $pk;
}

=head2 get_all_types

REST GET /attribute
    GET all attribute types

    response 200 : (AttributeDump) list of types of attributes

    schema AttributeDump: {
          "type": "array",
          "items" : {
            "$ref":  "#/definitions/AttributeDumpItem"
          }
    }

    schema AttributeDumpItem: {
          "required": ["api_name", "primary_field", "columns"],
          "properties" : {
            "api_name" : {
                "type" : "string",
                "example": "<<environment>>",
                "description" : "Textual representation of attribute"
            },
            "primary_field" : {
               "type" : "string",
                "example": "<<environment>>",
               "description" : "Primary field"
            },
             "columns": {
                 "type": "array",
                 "items": {
                     "$ref": "#/definitions/AttributeColumn"
                 }
            }
         }
    }

    schema AttributeColumn: {
           "required": ["description","attribute_type_name"],
           "properties": {
               "description": {
                   "$ref": "#/definitions/AttributeDescription"
               },
               "attribute_type_name": {
                   "$ref": "#/definitions/AttributeType"
               }
           }
    }

    schema AttributeDescription: {
           "required": ["data_type", "size"],
           "properties": {
               "data_type": { "type": "string", "example": "varchar", "description": "Database column type" },
               "documentation": { "type": "string", "example": "Description of this attribute type" },
               "is_nullable": { "type": "int", "example": "0" },
               "display_name": { "type": "string", "example": "Description" },
               "size": { "type": "int", "example": "32", "description": "Database column size" }
           }
    }

    schema AttributeType: {
           "required": ["data_type", "size"],
           "properties": {
               "data_type": { "type": "string", "example": "varchar", "description": "Database column type" },
               "documentation": { "type": "string", "example": "<<Environment (prod, qa, dev, etc.)>>" },
               "is_nullable": { "type": "int", "example": "0" },
               "display_name": { "type": "string", "example": "<<Environment>>" },
               "size": { "type": "int", "example": "32", "description": "Database column size" }
           }
    }

    schema Hash: {
           "description": "Arbitrary Hash",
           "properties": {
               "key": { "type": "any", "example": "value", "description": "Example key-value pair" }
           }
    }

    schema HashRef: {
           "description": "Arbitrary Hash",
           "properties": {
               "key": { "type": "any", "example": "value", "description": "Example key-value pair" }
           }
    }

    schema Array: {
           "description": "Arbitrary Array"
    }

=cut

sub get_all_types :GET Chained('base') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        return $self->simple_ok_with_result($c, $self->serialize_types($c, 'A'));
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, $ex->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 get_all_of_type

REST GET /attribute/$type
    GET all attributes of a type

    param $type  : (Str) [required] type of attribute
    response 200 : (Array[AttributeItem]) list of attributes of type $type XXXX

=cut

sub get_all_of_type :GET Chained('attribute_type') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my @rows = $c->stash->{attribute_rs}->search()->as_hash->all;
        return $self->simple_ok_with_result($c, \@rows);
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error getting attribute data: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 get_attribute

REST GET /attribute/$type/$name
    GET an attribute of type $type and name $name

    param $type  : (Str) [required] type of attribute
    param $name  : (Str) [required] name of attribute
    response 200 : (AttributeItem) attribute information

=cut

sub get_attribute :GET Chained('attribute_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my $row = $c->stash->{attribute_rs}->search({
            $c->stash->{primary_field} => $c->stash->{primary_field_value},
        })->as_hash->first;

        if ($row) {
            return $self->simple_ok_with_result($c, $row);
        }
        else {
            return $self->simple_not_found($c, "Attribute %s/%s not found", $c->stash->{attribute_type},
                $c->{stash}->{primary_field_value});
        }
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error getting attribute data: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 put_attribute

REST PUT /attribute/$type/$name
    Creates a new or updates an existing attribute.

    param $type  : (Str) [required] type of attribute
    param $name  : (Str) [required] name of attribute
    body         : (AttributeReqItem) [required]
    response 201 : (AttributeItem) attribute created

    schema AttributeItem:
       description: (Str) [required] Textual representation of attribute
       environment: (Str) Environment

    schema AttributeReqItem:
       description: (Str) [required] Textual representation of attribute

=cut

sub put_attribute :PUT Chained('attribute_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(admin-action) {
    my ($self, $c) = @_;

    $c->req->data->{$c->stash->{primary_field}} = $c->stash->{primary_field_value};

    try {
        my $attribute_row = $c->stash->{attribute_rs}->find($c->stash->{primary_field_value});
        if ($attribute_row) {
            # update
            $c->log->info("Update operation");
            $attribute_row->update($c->req->data) if %{$c->req->data};
        } else {
            # create
            $c->log->info("Create operation");
            $c->stash->{attribute_rs}->create($c->req->data);
        }
        my $final_result = $c->stash->{attribute_rs}->search({
            $c->stash->{primary_field} => $c->stash->{primary_field_value}
        })->as_hash->first;

        return $self->simple_created($c, $final_result);
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error creating/updating attribute: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: " . $err);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error creating/updating attribute: $err");
    }
}

=head2 delete_attribute

REST DELETE /attribute/$attribute_type/$primary_field_value
    Deletes an attribute.

    param $attribute_type      : (String) [required] attribute type
    param $primary_field_value : (String) [required] attribute primary field
    response 200               : Deleted


=cut

sub delete_attribute :DELETE Chained('attribute_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(admin-action) {
    my ($self, $c) = @_;

    try {
        my $attribute_row = $c->stash->{attribute_rs}->find($c->stash->{primary_field_value});

        if ($attribute_row) {
            $attribute_row->delete();
            return $self->simple_ok_without_result($c, "%s deleted.", $c->stash->{primary_field_value});
        }
        else {
            return $self->simple_not_found($c, "%s not found.", $c->stash->{primary_field_value});
        }
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error deleting attribute: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: " . $err);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error deleting attribute: $err");
    }
}

## use critic

__PACKAGE__->meta->make_immutable;
