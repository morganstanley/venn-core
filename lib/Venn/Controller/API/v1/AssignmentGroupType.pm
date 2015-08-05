package Venn::Controller::API::v1::AssignmentGroupType;

=head1 NAME

Venn::Controller::API::v1::AssignmentGroupType

=head1 DESCRIPTION

CRUD for Assignment Group Types.

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

=head1 METHODS

=cut

use v5.14;
use Moose;
use MooseX::ClassAttribute;
use namespace::autoclean;

use Data::Dumper;
use TryCatch;
use YAML::XS;

BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

## no critic (RequireFinalReturn)

=head1 METHODS

=head2 get_assignmentgrouptypes

REST GET /assignmentgrouptype
    GET all assignmentgrouptype types

    response 200 : (AGTResponse) A hash of defined assignment group types

=cut

sub get_assignmentgrouptypes :GET Path('assignmentgrouptype') Args(0) Does(Auth) AuthRole(ro-action) {
    my ( $self, $c, $name ) = @_;

    return $self->_list_all_agts($c);
}

=head2 get_assignmentgrouptype

REST GET /assignmentgrouptype/$name
    GET the assignmentgrouptype with name $name

    param $name  : (String) AGT name
    response 200 : (AGTResponse) AGT definition

    schema AGTResponse: {
        "properties": {
             "<assignment group name>": {
                 "$ref": "#/definitions/AGTDefinition"
             }
        }
    }

    schema AGTDefinition: {
        "required": ["description", "definition"],
        "properties": {
             "description": { "type": "string", "example": "example description" },
             "definition": { "type": "any", "example": "hash of AGT definition" }
        }
    }

=cut

sub get_assignmentgrouptype :GET Path('assignmentgrouptype') Args(1) Does(Auth) AuthRole(ro-action) {
    my ( $self, $c, $name ) = @_;

    return $self->_get_specific_agt($c, $name);
}

=head2 $self->_list_all_agts($c)

Lists all AssignmentGroup Types

=cut

sub _list_all_agts :Private {
    my ( $self, $c ) = @_;

    my %types;

    my @results = $c->model('VennDB::AssignmentGroup_Type')->search->as_hash->all;
    for my $row (@results) {
        $row->{definition} = YAML::XS::Load($row->{definition});
        $types{$row->{assignmentgroup_type_name}} = $row;
        delete $row->{assignmentgroup_type_name};
    }

    return $self->simple_ok($c, \%types);
}

=head2 _get_specific_agt

Gets the specified AssignmentGroup Type

=cut

sub _get_specific_agt :Private {
    my ( $self, $c, $name ) = @_;

    my $row = $c->model('VennDB::AssignmentGroup_Type')
        ->as_hash
        ->single({ assignmentgroup_type_name => $name });

    if ($row) {
        $c->log->info("GET request for AssignmentGroup Type $name successful");
        $row->{definition} = YAML::XS::Load($row->{definition});
        my $real_name = delete $row->{assignmentgroup_type_name};
        return $self->simple_ok($c, { $real_name => $row });
    }
    else {
        $c->log->warn("GET request for AssignmentGroup Type $name unsuccessful");
        return $self->simple_not_found($c, "$name not found");
    }
}

=head2 put_assignmentgrouptype

REST PUT /assignmentgrouptype/$name
    Creates or updates the AssignmentGroup Type

    param $name  : (String) Name of the AssignmentGroup Type [required]
    body: (FullAGTDefinition) AGT specification [required]
    response 200 : (FullAGTDefinition) Updated
    response 201 : (FullAGTDefinition) Created

    schema FullAGTDefinition: {
        "required": ["assignmentgroup_type_name", "description", "definition"],
        "properties": {
             "assignmentgroup_type_name": { "type": "string", "example": "my_agt" },
             "description": { "type": "string", "example": "example description" },
             "definition": { "type": "any", "example": "hash of AGT definition" }
        }
    }

=cut

around 'put_assignmentgrouptype' => sub {
    my $orig = shift;
    my $self = shift;
    my ($c, $name) = @_;

    unless ( defined $c->req->data && defined $name ) {
        return $self->status_bad_request(
            $c,
            entity => {
                success => 0,
                error   => "Missing required data: payload and/or name",
                received => {
                    payload             => defined $c->req->data ? $c->req->data : 'NULL',
                    name                => defined $name ? $name : 'NULL',
                },
            },
        );
    }

    return $self->$orig(@_);
};

sub put_assignmentgrouptype :PUT Path('assignmentgrouptype') Args(1) Does(Auth) AuthRole(dev-action) {
    my ( $self, $c, $name ) = @_;

    try {
        $c->log->debug("PUT request for Assignment Group Type $name: " . Dumper($c->req->data));

        my $rs = $c->model('VennDB::AssignmentGroup_Type');

        my $row = $rs->single({ assignmentgroup_type_name => $name });
        if ($row) {
            $row->update($c->req->data);
            return $self->simple_ok($c, $row);
        }
        else {
            $row = $rs->create($c->req->data);
            $c->log->info("PUT request for Assignment Group Type $name successful");
            return $self->simple_created($c, $row);
        }
    }
    catch (VennException $ex) {
        $c->log->error("PUT request for Assignment Group Type $name unsuccessful: " . $ex->as_string_no_trace);
        return $self->simple_internal_server_error($c, "Error creating/updating provider: " . $ex->as_string_no_trace);
    }
    catch ($ex) {
        $c->log->error("PUT request for Assignment Group Type $name unsuccessful: $ex");
        return $self->simple_bad_request($c, "Error creating/updating provider: $ex");
    }
}

=head2 delete_assignmentgrouptype

REST DELETE /assignmentgrouptype/$name
    DELETE the AssignmentGroup Type

    param $name  : (String) Name of the AssignmentGroup Type [required]
    response 200 : Success

=cut

around 'delete_assignmentgrouptype' => sub {
    my $orig = shift;
    my $self = shift;
    my ($c, $name) = @_;

    return $self->simple_bad_request($c, "AssignmentGroup Type name not specified.") unless defined $name;

    return $self->$orig(@_);
};

sub delete_assignmentgrouptype :DELETE Path('assignmentgrouptype') Args(1) Does(Auth) AuthRole(dev-action) {
    my ( $self, $c, $name ) = @_;

    my $row = $c->model('VennDB::AssignmentGroup_Type')->single({ assignmentgroup_type_name => $name });

    if ($row) {
        $row->delete();

        $c->log->info("DELETE request successful for Assignment Group Type $name");
        $self->simple_ok_without_result($c, "$name deleted");
    }
    else {
        $c->log->error("DELETE request unsuccessful for Assignment Group Type $name");
        $self->simple_not_found($c, "$name not found");
    }
}

## no critic
__PACKAGE__->meta->make_immutable;
