package Venn::Controller::API::v1::AssignmentGroup;

=head1 NAME

Venn::Controller::API::v1::AssignmentGroup

=head1 DESCRIPTION

Displays, creates, updates, and deletes AssignmentGroups.

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

=head1 ATTRIBUTES

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

=head2 get_assignmentgroup

REST GET /assignmentgroup/$lookup_column/$lookup_value
    Display an assignment group with
    $lookup_column (identifier or friendly) set to $lookup_value

    param $lookup_column   : (String) literally "identifier" or "friendly" [required]
    param $lookup_value    : (String) the value of the identifier or friendly [required]
    param with_metadata    : (Int) value 1 includes ag metadata information
    param with_assignments : (Int) value 1 includes ag assignments
    response 200           : (AssignmentGroup) assignment group details

    schema AssignmentGroup: {
      "required": ["assignmentgroup_id", "assignmentgroup_type_name", "identifier", "friendly", "created"],
      "properties": {
        "assignmentgroup_id": { "type": "string", "example": 1998 },
        "assignmentgroup_type_name": { "type": "string", "example": "zlight" },
        "identifier": { "type": "string", "example": "7B3408A8-F357-11E4-B3F1-C042E28D936B" },
        "friendly": { "type": "string", "example": "evm1111262" },
        "created": { "type": "integer", "example": 1430852977 }
       }
    }

=cut

sub get_assignmentgroup :GET Path('assignmentgroup') Args(2) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $lookup_column, $lookup_value) = @_;

    my %search_params;

    if (! defined $lookup_value || ! defined $lookup_column ) {
        return $self->simple_bad_request($c, "A lookup type and value are both required");
    }
    if (defined $lookup_column) {
        $self->_verify_valid_lookup_column($c, $lookup_column);
        $c->log->debug(sprintf("Lookup: %s => %s", $lookup_column, $lookup_value));
        $search_params{$lookup_column} = $lookup_value;
    }
    $c->log->debug("Search params: " . Dumper(\%search_params));

    my %attrs = ( columns => [qw/ assignmentgroup_id assignmentgroup_type_name friendly identifier created /] );
    push(@{$attrs{columns}}, 'metadata') if $c->req->param('with_metadata');

    my $rs = $c->model('VennDB::AssignmentGroup')
        ->search_with_query_params($c)
        ->search_readonly(\%search_params, \%attrs);

    $rs = $rs->with_assignments($c->req->param('with_assignment_provider')) if $c->req->param('with_assignments');

    my @records = $rs->as_hash->all;
    $self->inflate_yaml_columns([qw/ metadata /], \@records);
    if ($c->req->param('with_assignments') && $c->req->param('with_assignment_provider')) {
        $c->model('VennDB::AssignmentGroup')->flatten_assignment_data(\@records);
    }

    if ($lookup_column && $lookup_value) {
        if (@records) {
            return $self->simple_ok($c, $records[0]);
        }
        else {
            return $self->simple_not_found($c, "AssignmentGroup $lookup_column as $lookup_value not found");
        }
    }
    else {
        return $self->simple_ok($c, \@records);
    }
}

=head2 put_assignmentgroup

REST PUT /assignmentgroup/$lookup_column/$lookup_value
    Updates an existing AssignmentGroup.

    param $lookup_column : (String) literally "identifier" or "friendly" [required]
    param $lookup_value  : (String) the value of the identifier or friendly [required]
    response 200         : (AssignmentGroup) Successfully updated AGT

=cut

around 'put_assignmentgroup' => sub {
    my $orig = shift;
    my $self = shift;
    my ($c, $lookup_column, $lookup_value) = @_;

    # verify data + uri params
    unless ( defined $c->req->data && defined $lookup_column && defined $lookup_value ) {
        return $self->status_bad_request(
            $c,
            entity => {
                success => 0,
                error   => "Missing required data: data, lookup column and/or lookup value",
                received => {
                    data                 => defined $c->req->data ? $c->req->data : 'NULL',
                    lookup_column        => defined $lookup_column ? $lookup_column : 'NULL',
                    lookup_value         => defined $lookup_value ? $lookup_value : 'NULL',
                },
            },
        );
    }

    $self->_verify_valid_lookup_column($c, $lookup_column); # verify lookup_column is valid

    delete $c->req->data->{assignmentgroup_id}; # cannot change identifier
    return $self->$orig(@_);
};

sub put_assignmentgroup :PUT Path('assignmentgroup') Args(2) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $lookup_column, $lookup_value) = @_;

    $c->log->debug("PUT request for AssignmentGroup $lookup_column => $lookup_value: " . Dumper($c->req->data));

    my $error;
    try {
        my $row = $c->model('VennDB::AssignmentGroup')->single({
            $lookup_column            => $lookup_value,
        });

        if ($row) {
            # if it exists, update it
            $row->update($c->req->data);
            $c->log->info("PUT request for AssignmentGroup $lookup_column => $lookup_value successful (updated existing)");

            return $self->simple_ok($c, $row, "Updated Assignment Group %s", $row->identifier);
        }
        else {
            return $self->bad_request($c, "Assignment Group does not exist");
        }
    }
    catch ($err) {
        $error = "Error creating Assignment Group: $err";
    }

    $c->log->error("PUT request for AssignmentGroup $lookup_column => $lookup_value unsuccessful: $error");
    return $self->status_bad_request(
        $c,
        entity => {
            success => 0,
            error   => $error,
        },
    );
}

=head2 delete_assignmentgroup

REST DELETE /assignmentgroup/$lookup_column/$lookup_value
    Deletes existing AssignmentGroups. - Not currently implemented

=cut

around 'delete_assignmentgroup' => sub {
    my $orig = shift;
    my $self = shift;
    my ($c, $lookup_column, $lookup_value) = @_;

    $self->_verify_valid_lookup_column($c, $lookup_column);

    die "Not implemented\n";
    #return $self->$orig(@_);
};

sub delete_assignmentgroup :DELETE Path('assignmentgroup') Args(2) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $lookup_column, $lookup_value) = @_;

    my $row = $c->model('VennDB::AssignmentGroup')->single({
        $lookup_column            => $lookup_value,
    });

    if ($row) {
        my $id = $row->assignmentgroup_id;

        if ($row->delete()) {
            $c->log->info("DELETE request successful for AssignmentGroup $id ( $lookup_column => $lookup_value )");
            $self->simple_ok_without_result($c, "AssignmentGroup %s ( '%s' = '%s' ) deleted.", $id, $lookup_column, $lookup_value);
        }
        else {
            $self->simple_forbidden($c, "Error deleting AssignmentGroup $id");
        }
    }
    else {
        $c->log->info("DELETE request unsuccessful for AssignmentGroup $lookup_column => $lookup_value");
        $self->simple_not_found($c, "AssignmentGroup '%s' = '%s' not found.", $lookup_column, $lookup_value);
    }
}

=head2 store_metadata

REST POST /store_metadata/$identifier    <assignmentgroup>
    Store information in the assignment group's metadata

    param $identifier : (String) Assignment Group identifier [required]
    body              : (String) YAML serialized string to store [required]
    response 200      : Success

Expected data:
---
hostname: izvm2504.devin3.ms.com

=cut

sub store_metadata :POST Path('store_metadata') Args(1) Does(Auth) AuthRole(admin-action) {
    my ( $self, $c, $identifier ) = @_;

    try {
        my $result = $c->model('VennDB::AssignmentGroup')
            ->find_by_identifier($identifier)
            ->update_metadata($c->req->data);

        return $self->status_ok(
            $c,
            entity => {
                success => 1,
                message => "Stored in metadata",
            },
        );
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }
}

sub _verify_valid_lookup_column {
    my ( $self, $c, $column ) = @_;

    state $valid_columns = [qw/ friendly identifier /];
    if ( defined $column && $column ~~ @$valid_columns ) {
        return $self->simple_bad_request($c,
            "You may only use lookup columns '%s', you specified %s",
            join(', ', @$valid_columns), $column,
        );
    }

    return 1;
}

## use critic

=head1 AUTHOR

Venn Engineering

=cut

__PACKAGE__->meta->make_immutable;
