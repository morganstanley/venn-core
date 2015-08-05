package Venn::Controller::API::v1::Provider;

=head1 NAME

Venn::Controller::API::v1::Provider - Provider CRUD

=head1 DESCRIPTION

RESTful interface for providers in Venn.

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

use TryCatch;
use Venn::Types qw(:all);
use Venn::Exception qw(
    API::InvalidProviderType
);

## no critic (RequireFinalReturn,RequireArgUnpacking)

=head1 METHODS

=head2 provider_base

Provider base.

=cut

sub provider_base :Chained('/') PathPart('api/v1/provider') CaptureArgs(0) { }

=head2 provider_type

Captures provider type into the stash (provider_type, source, primary_field, container_field)

    Stashes:
    provider_type: the provider type (e.g. esxram, nas, filerio)
    source: the P_* class for the provider
    primary_field: the primary field of the table (e.g. cluter_name, filer_name)
    container_field: the field containing the name of provider's container (e.g. rack_name)

=cut

sub provider_type :Chained('provider_base') PathPart('') CaptureArgs(1) {
    my ($self, $c, $type) = @_;

    try {
        $c->stash->{provider_type}   = $type;
        my %map = %{ Venn::Schema->provider_mapping->{$type} };
        unless (%map) {
            $self->simple_not_found($c, "Provider type '%s' not found", $type);
            $c->detach();
        }
        $c->stash->{source}          = $map{source};
        $c->stash->{primary_field}   = $map{primary_field};
        $c->stash->{container_field} = $map{container_field};
        $c->stash->{subprovider_rs}  = $c->model('VennDB::' . $c->stash->{source});
    }
    catch (VennException $ex) {
        $self->simple_bad_request($c, $ex->as_string_no_trace);
        $c->detach();
    }
    catch ($ex) {
        $self->simple_internal_server_error($c, $ex);
        $c->detach();
    }
}

=head2 provider_known_pk

Captures the known provider (its primary_field_value) and generates the subprovider's ResultSet

    Stashes:
    primary_field_value: primary field (e.g. the actual cluster_name, dzecl123)
    subprovider_rs: ResultSet for the subprovider (P_* class)

=cut

sub provider_known_pk :Chained('provider_type') PathPart('') CaptureArgs(1) {
    my ($self, $c, $pk) = @_;
    $c->stash->{primary_field_value} = $pk;
}

=head2 provider_attr_type

Looks up the provider for all of the attr REST methods.

    Stashes:
    subprovider: the subprovider (P_* class) Result
    provider: the subprovider's base provider Result

=cut

sub provider_attr_type :Chained('provider_known_pk') PathPart('') CaptureArgs(1) {
    my ($self, $c, $attr_type) = @_;
    $c->stash->{attr_type} = $attr_type;
    try {
        $c->log->debug("Looking up " . $c->stash->{primary_field_value});
        $c->stash->{subprovider} = $c->stash->{subprovider_rs}->find_by_primary_field($c->stash->{primary_field_value});
        if (! $c->stash->{subprovider}) {
            $self->simple_not_found($c, "Provider not found");
            $c->detach();
        }
        else {
            $c->stash->{provider} = $c->stash->{subprovider}->provider;
        }
    }
    catch (VennException $ex) {
        $self->simple_not_found($c, $ex->as_string_no_trace);
        $c->detach();
    }
    catch ($err) {
        $self->simple_internal_server_error($c, $err);
        $c->detach();
    }
}

=head2 get_all

REST GET /provider
    List all providers

    response 200 : (Array[Provider]) providers

    schema Provider: {
      "required": ["provider_id", "providertype_name", "state_name", "size", "available_date", "overcommit_ratio"],
      "properties": {
        "provider_id": { "type": "integer", "description": "provider ID", "example": 524 },
        "providertype_name": { "type": "string", "description": "provider type", "example": "cpu" },
        "state_name": { "type": "string", "description": "state of availability", "example": "active" },
        "size": { "type": "integer", "description": "maximum resources provided", "example": 200 },
        "available_date": { "type": "integer", "description": "timestamp of first availability", "example": 1430771325 },
        "overcommit_ratio": { "type": "number", "description": "resource size multiplier for placement capacity", "example": 1.5 }
      }
    }

=cut

sub get_all :GET Chained('provider_base') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my @records = $c->model('VennDB::Provider')->search->all;
        #my @records = $c->model('VennDB::Provider')
        #->search_with_query_params($c) #XXX: FIXME
        #->prefetch_all_types
        #->as_flat_hash
        #->all;
        return $self->simple_ok_with_result($c, \@records);
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, $ex->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }
}

=head2 get_all_of_type

REST GET /provider/$type
    GET all providers of provider type $type

    param $type  : (String) provider type [required]
    response 200 : (Array[Provider]) List of providers

=cut

sub get_all_of_type :GET Chained('provider_type') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my @records = $c->stash->{subprovider_rs}
            ->with_provider
            ->search_with_query_params($c)
            ->as_hash
            ->all;
        for my $rec (@records) {
            $rec->{metadata} = {
                primary_field   => $c->stash->{primary_field},
                container_field => $c->stash->{container_field},
            };
        }
        return $self->simple_ok_with_result($c, \@records) if scalar @records > 0;
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, $ex->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }

    return $self->simple_not_found($c, "No providers found");
}

=head2 get_provider

REST GET /provider/$type/$pk
    GET a specific provider

    param $type  : (String) provider type [required]
    param $pk    : (String) provider primary key [required]
    response 200 : (Provider) provider

=cut

sub get_provider :GET Chained('provider_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my $row = $c->stash->{subprovider_rs}
            ->with_provider
            ->search({ $c->stash->{primary_field} => $c->stash->{primary_field_value} })
            ->as_hash
            ->first;
        if ($row) {
            $row->{metadata} = {
                primary_field   => $c->stash->{primary_field},
                container_field => $c->stash->{container_field},
            };
            return $self->simple_ok_with_result($c, $row) if $row;
        }
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, $ex->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, $err);
    }

    return $self->simple_not_found($c, "No providers found");
}

=head2 put_provider

REST PUT /provider/$type/$pk
    Create/update a provider

    param $type  : (String) provider type [required]
    param $pk    : (String) provider primary key [required]
    body         : (Provider) provider information
    response 201 : provider created/updated

=cut

sub put_provider :PUT Chained('provider_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(dev-action) {
    my ($self, $c) = @_;

    try {
        my $provider_id;

        # look for the row in the database
        my $subprovider_row = $c->stash->{subprovider_rs}->find_by_primary_field($c->stash->{primary_field_value});
        if ($subprovider_row) {
            $c->log->debug("Update detected");
            $c->model('VennDB')->schema->txn_do(sub {
                $subprovider_row->update($c->req->data);
            });
            $provider_id = $subprovider_row->provider_id;
        }
        else {
            $c->log->debug("Create detected");

            # Add the primary field + value from the path to the data being submitted
            # e.g. PUT $api/provider/esxram/zyecl1 will add { cluster_name => zyecl1 }
            $c->req->data->{$c->stash->{primary_field}} = $c->stash->{primary_field_value};

            $provider_id = $c->stash->{subprovider_rs}->create_with_provider($c->req->data);
        }
        $c->log->infof("PUT request for %s %s successful", $c->stash->{source}, $c->stash->{primary_field_value});

        my $result_row = $c->stash->{subprovider_rs}
            ->with_provider
            ->single({ 'me.provider_id' => $provider_id });
        return $self->simple_created($c, $result_row->TO_JSON);
    }
    catch (VennException $err) {
        return $self->simple_internal_server_error($c, "Venn error creating provider: " . $err->as_string_no_trace);
    }
    catch (DBIxException $err) {
        return $self->simple_bad_request($c, "Database Error: $err");
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error creating provider: $err");
    }
}

=head2 delete_provider

REST DELETE /provider/$type/$pk
    DELETE a provider.

    param $type  : (String) provider type [required]
    param $pk    : (String) provider primary key [required]
    response 200 : provider removed

=cut

sub delete_provider :DELETE Chained('provider_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(dev-action) {
    my ($self, $c) = @_;

    my $provider_row = $c->stash->{subprovider_rs}->find_by_primary_field($c->stash->{primary_field_value});

    if ($provider_row) {
        $provider_row->delete();

        $c->log->infof("DELETE request successful for %s %s", $c->stash->{source}, $c->stash->{primary_field_value});
        return $self->simple_ok_without_result($c, "%s deleted.", $c->stash->{primary_field_value});
    }
    else {
        $c->log->error("DELETE request unsuccessful for %s %s", $c->stash->{source}, $c->stash->{primary_field_value});
        return $self->simple_not_found($c, "%s not found", $c->stash->{primary_field_value});
    }
}

=head2 get_all_of_attr_type

REST GET provider/$type/$pk/$attr_type
    GET all mapped attributes of a specific type

    param $type      : (String) provider type [required]
    param $pk        : (String) provider primary key [required]
    param $attr_type : (String) attribute type [required]
    response 200     : (AttributeDump) mapped attributes

=cut

sub get_all_of_attr_type :GET Chained('provider_attr_type') PathPart('') Args(0)  {
    my ($self, $c) = @_;

    try {
        my $attrs = $c->stash->{provider}->mapped_attributes_of_type($c->stash->{attr_type});
        return $self->simple_ok_with_result($c, $attrs);
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, "Error getting attribute values: %s", $ex->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error getting attribute values: %s", $err);
    }
}

=head2 get_attr

REST GET /provider/$type/$pk/$attr_type/$attr_value
    GET the attribute if it has been mapped to this provider.

    param $type       : (String) provider type [required]
    param $pk         : (String) provider primary key [required]
    param $attr_type  : (String) attribute type [required]
    param $attr_value : (String) attribute type [required]
    response 200      : (AttributeDumpItem) attribute mapped

=cut

sub get_attr :GET Chained('provider_attr_type') PathPart('') Args(1) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $attr_value) = @_;

    try {
        my $info = $c->stash->{provider}->get_attribute_info($c->stash->{attr_type}, $attr_value);
        if ($info) {
            return $self->simple_ok_with_result($c, $info->TO_JSON);
        }
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, "Error getting attribute values: %s", $ex->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error getting attribute values: %s", $err);
    }

    return $self->simple_not_found($c, "Attribute value %s not mapped to provider", $attr_value);
}

=head2 put_attr

REST PUT /provider/$type/$pk/$attr_type/$attr_value
    Maps an attribute to a provider

    param $type       : (String) provider type [required]
    param $pk         : (String) provider primary key [required]
    param $attr_type  : (String) attribute type [required]
    param $attr_value : (String) attribute type [required]
    response 200      : created mapping

=cut

sub put_attr :PUT Chained('provider_attr_type') PathPart('') Args(1) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $attr_value) = @_;

    try {
        $c->stash->{provider}->map_attribute($c->stash->{attr_type}, $attr_value);
        return $self->simple_ok_without_result($c);
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, "Error getting attribute values: %s", $ex->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error getting attribute values: %s", $err);
    }
}

=head2 delete_attr

REST DELETE /provider/$type/$pk/$attr_type/$attr_value
    Unmaps an attribute from a provider

    param $type       : (String) provider type [required]
    param $pk         : (String) provider primary key [required]
    param $attr_type  : (String) attribute type [required]
    param $attr_value : (String) attribute type [required]
    response 200      : successfully deleted mapping

=cut

sub delete_attr :DELETE Chained('provider_attr_type') PathPart('') Args(1) Does(Auth) AuthRole(admin-action) {
    my ($self, $c, $attr_value) = @_;

    try {
        $c->stash->{provider}->unmap_attribute($c->stash->{attr_type}, $attr_value);
        return $self->simple_ok_without_result($c);
    }
    catch (VennException $ex) {
        return $self->simple_bad_request($c, "Error getting attribute values: %s", $ex->as_string_no_trace);
    }
    catch ($err) {
        return $self->simple_internal_server_error($c, "Error getting attribute values: %s", $err);
    }
}

## use critic

__PACKAGE__->meta->make_immutable;
