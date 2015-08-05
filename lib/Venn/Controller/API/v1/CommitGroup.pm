package Venn::Controller::API::v1::CommitGroup;

=head1 NAME

Venn::Controller::API::v1::CommitGroup

=head1 DESCRIPTION

Displays, commits and deletes assignments commit groups.
A commit group is a grouping of assignments.

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
    with    qw(
        Venn::ControllerRole::API::Results
        Venn::Role::Logging
    );
}

use TryCatch;
use YAML::XS;

use Venn::Exception qw(
    API::InvalidCommitGroup
);

## no critic (RequireFinalReturn)

=head1 METHODS

=head2 get_commit_group

REST GET /commit_group/$uuid
    GET assignments for a commit_group

    param $uuid  : (String) [required] commit group UUID
    response 200 : (Array[Assignment]) List of assignments in commit group

=cut

sub get_commit_group :GET Path('commit_group') Args(1) Does(Auth) AuthRole(ro-action) {
    my ( $self, $c, $commit_group_id ) = @_;

    try {
        my @assignments = $c->model('VennDB::Assignment')
            ->search_by_commit_group_id($commit_group_id)->as_hash->all;

        if (scalar(@assignments) > 0) {
            $c->log->info("GET request for commit_group successful");
            return $self->simple_ok($c, \@assignments);
        }
        else {
            $c->log->warn("GET request for commit_group unsuccessful");
            return $self->simple_not_found($c, "Assignments not found for commit_group");
        }
    }
    catch ($e) {
        return $self->simple_internal_server_error($c, "Unexpected error: $e");
    }
}

=head2 post_commit_group

REST POST /commit_group/$uuid
    Commit assignments for a commit_group

    param $uuid  : (String) [required] commit group UUID
    response 200 : Successfully committed assignments

=cut

sub post_commit_group :POST Path('commit_group') Args(1) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $commit_group_id) = @_;
    my $schema = $c->model('VennDB')->schema;
    try {
        $schema->txn_do(sub {
            my $assignments = $c->model('VennDB::Assignment')
                ->search_uncommitted_by_commit_group_id($commit_group_id);

            $c->log->debug("Committing assignments for commit group: $commit_group_id");
            while (my $assignment = $assignments->next) {
                $assignment->committed(time());
                $assignment->update();
            }
        });

        return $self->status_ok(
            $c,
            entity => {
                success => 1,
                message => "Assignments for commit_group_id $commit_group_id committted",
            },
        );
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }
}

=head2 delete_commit_group

REST DELETE /commit_group/$uuid
    DELETE uncommitted assignments for a Commit Group

    param $uuid  : (String) [required] commit group UUID
    response 200 : Success

=cut

sub delete_commit_group :DELETE Path('commit_group') Args(1) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $commit_group_id) = @_;
    my $schema = $c->model('VennDB')->schema;

    try {
        $schema->txn_do(sub {
            my $assignments = $c->model('VennDB::Assignment')
                ->search_uncommitted_by_commit_group_id($commit_group_id);

            my $first_assignment = $assignments->first;
            if (not defined $first_assignment) {
                $self->log->tracef("Commit group not found: %s", $commit_group_id);
                Venn::Exception::API::InvalidCommitGroup->throw({
                    commit_group_id => $commit_group_id,
                });
            }

            my $ag_id = $first_assignment->assignmentgroup_id;

            $c->log->debug("Deleting assignments for commit_group: $commit_group_id");
            $assignments->delete_all();

            # If the AG has no other assignments, delete it
            my $remaining_assignments = $c->model('VennDB::Assignment')
                ->search_by_assignmentgroup_id($ag_id);
            if (not defined $remaining_assignments->first) {
                $c->log->debug("Deleting assignments for assignmentgroup_id: $ag_id");
                $c->model('VennDB::AssignmentGroup')->find($ag_id)->delete();
            }

            return $self->simple_ok_without_result($c, "Assignments for commit_group_id %s deleted", $commit_group_id);
        });
    }
    catch ($err where { $_->isa('Venn::Exception::API::InvalidCommitGroup') }) {
        return $self->simple_not_found($c, "Error deleting commit group: %s", $err->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "An error occurred: $err");
    }
}

## use critic

__PACKAGE__->meta->make_immutable;
