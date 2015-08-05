package Venn::Controller::API::v1::Provider_State;

=head1 NAME

Venn::Controller::API::v1::Provider_State - Provider State CRUD

=head1 DESCRIPTION

RESTful interface for provider states in Venn.

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

=head2 get_all_provider_states

REST GET /provider_state
    List all provider states

    response 200 : (Array[String]) provider states

=cut

sub get_all_provider_states :GET Path('provider_state') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my @states;
        if ($c->req->param('data')) {
            @states = $c->model('VennDB::Provider_State')->search->as_hash->all;
        }
        else {
            my @rows = $c->model('VennDB::Provider_State')
                ->search(undef, { columns => 'state_name' })->as_hash->all;
            @states = map { $_->{state_name} } @rows;
        }
        return $self->simple_ok_with_result($c, \@states);
    }
    catch (VennException $ex) {
        return $self->simple_not_found($c, $ex->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_bad_request($c, $err);
    }
}

=head2 get_provider_state

REST GET /provider_state/$state
    GET details of provider state $state

    param $state : (String) provider state
    response 200 : (ProviderStateItem) provider state info

=cut

sub get_provider_state :GET Path('provider_state') Args(1) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $state_name) = @_;

    try {
        my $provider_state = $c->model("VennDB::Provider_State")->find($state_name);
        if ($provider_state) {
            return $self->simple_ok_with_result($c, $provider_state->TO_JSON);
        }
        else {
            Venn::Exception::API::InvalidProviderState->throw({ provider_state => $state_name });
        }
    }
    catch (VennException $ex) {
        return $self->simple_not_found($c, $ex->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_bad_request($c, $err);
    }
}

=head2 put_provider_state

REST PUT /provider_state/$state_name
    Creates a new or updates an existing provider_state.

    param $state_name  : (Str) [required] name of provider_state
    body               : (ProviderStateItem) [required]
    response 200       : (ProviderStateItem) provider_state updated
    response 201       : (ProviderStateItem) provider_state created

    schema ProviderStateItem: {
        "required": ["state_name", "description"],
        "properties": {
            "state_name": { "type": "string", "example": "active", "description": "State name" },
            "description": { "type": "string", "example": "description of active", "description": "Description" }
        }
    }

=cut

sub put_provider_state :PUT Path('provider_state') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $state_name) = @_;

    my $rs = $c->model("VennDB::Provider_State");
    try {
        my $row = $rs->find($state_name);
        if ($row) {
            # update
            $c->log->info("Update operation");
            $row->update($c->req->data) if %{$c->req->data};

            my $final_result = $rs->find($state_name);
            return $self->simple_ok_with_result($c, $final_result);
        }
        else {
            # create
            $c->log->info("Create operation");
            $c->req->data->{state_name} = $state_name;
            $rs->create($c->req->data);

            my $final_result = $rs->find($state_name);
            return $self->simple_created($c, $final_result);
        }
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error creating/updating provider_state: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: " . $err);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error creating/updating provider_state: $err");
    }
}

=head2 delete_provider_state

REST DELETE /provider_state/$state_name
    Deletes a provider_state.

    param $state_name      : (String) [required] provider_state name
    response 200           : Deleted

=cut

sub delete_provider_state :DELETE Path('provider_state') Args(1) Does(Auth) AuthRole(dev-action) {
    my ($self, $c, $state_name) = @_;

    try {
        my $row = $c->model("VennDB::Provider_State")->find($state_name);

        if ($row) {
            $row->delete();
            return $self->simple_ok_without_result($c, "%s deleted.", $state_name);
        }
        else {
            return $self->simple_not_found($c, "%s not found.", $state_name);
        }
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error deleting provider_state: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: " . $err);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error deleting provider_state: $err");
    }
}

## use critic

__PACKAGE__->meta->make_immutable;
