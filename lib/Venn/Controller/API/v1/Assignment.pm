package Venn::Controller::API::v1::Assignment;

=head1 NAME

Venn::Controller::API::v1::Assignment

=head1 DESCRIPTION

Displays and commits assignments.

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

BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

use Data::Dumper;
use TryCatch;

use Venn::Exception qw( API::InvalidSortPair );
use Venn::Types qw(:all);

## no critic (RequireFinalReturn)

=head1 METHODS

=head2 get_assignment

REST GET /assignment/$id
    GET only assignment $id

    param $id    : (Int) assignment ID [required]
    response 200 : (Assignment) assignment details

    schema Assignment: {
      "required": ["commit_group_id", "provider_id", "assignmentgroup_id", "size", "commit_group_id"],
      "properties": {
        "commit_group_id":    { "type": "string", "description": "UUID of commit group", "example": "4635BA68-F35A-11E4-B84B-B4A95DE31A44" },
        "provider_id":        { "type": "integer", "description": "ID of provider", "format": "int32", "example": 532 },
        "assignmentgroup_id": { "type": "integer", "description": "ID of assignment group", "format": "int32", "example": 4567 },
        "size":               { "type": "integer", "format": "int32", "example": 100 },
        "created":            { "type": "integer", "description": "timestamp of creation", "format": "int64", "example": 1430852977 },
        "committed":          { "type": "integer", "description": "timestamp of commitment", "format": "int64", "example": 1430852977 },
        "resource_id":        { "type": "integer", "description": "named resource ID (if exists), otherwise null", "format": "int32", "example": 987 },
        "message":            { "type": "string", "description": "optional message for operation result" }
      }
    }

=cut

sub get_assignment :GET Path('assignment') Args(1) Does(Auth) AuthRole(ro-action) {
    my ( $self, $c, $id ) = @_;

    my @records;
    try {
        my $rs = $c->model('VennDB::Assignment');
        if (defined $id) {
            my $result = $rs->as_hash
                            ->search_readonly
                            ->single({ assignment_id => $id });
            if ($id) {
                return $self->simple_ok($c, $result);
            }
            else {
                return $self->simple_not_found($c, "Assignment $id not found");
            }
        }
        else {
            @records = $rs
                ->search_readonly
                ->search_with_query_params($c)
                ->as_hash
                ->all;
            return $self->simple_ok($c, \@records);
        }
    }
    catch (VennException $e) {
        return $self->simple_internal_server_error($c, $e->as_string_no_trace);
    }
    catch ($e) {
        return $self->simple_internal_server_error($c, "Unexpected error: $e");
    }
}

=head2 post_assignment

REST POST /assignment/$id/commit
    Commit an assignment

    param $id    : (Int) assignment ID [required]
    response 200 : (Assignment) assignment is committed

=cut

around 'post_assignment' => sub {
    my $orig = shift;
    my $self = shift;
    my ($c, $id, $action) = @_;

    unless ( defined $id ) {
        return $self->status_bad_request(
            $c,
            entity => {
                success  => 0,
                error    => "Missing required data: id",
                received => {
                    id => defined $id ? $id : 'NULL',
                },
            },
        );
    }

    return $self->$orig(@_);
};

sub post_assignment :POST Path('assignment') Args(2) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $id, $action) = @_;

    my $assignment = $c->model('VennDB::Assignment')->single({ assignment_id => $id });

    return $self->simple_bad_request($c, "No action specified") unless defined $action;

    given ($action) {
        when (/^commit$/) {
            if ($assignment->committed) {
                return $self->simple_ok($c, { $assignment->get_columns() }, "Assignment $id is already been committed");
            }
            else {
                $assignment->committed(time());
                if ($assignment->update()) {
                    return $self->simple_ok($c, { $assignment->get_columns() }, "Assignment $id committed");
                }
                else {
                    return $self->simple_forbidden($c, "Error committing Assignment $id");
                }
            }
        }
        default {
            return $self->simple_bad_request($c, "Unknown action: $action");
        }
    }
}

## use critic
__PACKAGE__->meta->make_immutable;
