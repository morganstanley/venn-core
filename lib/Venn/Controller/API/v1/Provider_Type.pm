package Venn::Controller::API::v1::Provider_Type;

=head1 NAME

Venn::Controller::API::v1::Provider_Type - Provider_Type CRUD

=head1 DESCRIPTION

RESTful interface for provider types in Venn.

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
use TryCatch;

BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

use Venn::Types qw(:all);
use Venn::Exception qw(
    API::InvalidProviderType
);

## no critic (RequireFinalReturn)

=head1 METHODS

=head2 get_all_provider_types

REST GET /provider_type
    List all provider types

    response 200 : (Array[String]) provider types

=cut

sub get_all_provider_types :GET Path('provider_type') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my @types;
        if ($c->req->param('data')) {
            @types = $c->model('VennDB::Provider_Type')
                ->search->as_hash->all;
        }
        else {
            my @rows = $c->model('VennDB::Provider_Type')
                ->search(undef, { columns => 'providertype_name' })->as_hash->all;
            @types = map { $_->{providertype_name} } @rows;
        }
        return $self->simple_ok_with_result($c, \@types);
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

=head2 get_provider_type

REST GET /provider_type/$type
    GET details of provider type $type

    param $type  : (String) provider type [required]
    response 200 : (ProviderType) provider type

    schema ProviderType: {
      "required": ["overcommit_ratio", "unit", "providertype_name", "category", "description"],
      "properties": {
        "overcommit_ratio": { "type": "number", "description": "resource size multiplier for placement capacity", "example": 4.0 },
        "unit": { "type": "string", "description": "measurement units", "example": "cores" },
        "providertype_name": { "type": "string", "description": "provider type name", "example": "cpu" },
        "category": { "type": "string", "description": "provider type category", "example": "compute" },
        "description": { "type": "string", "example": "Provider: Cpu (Esx Cluster)" }
      }
    }

=cut

sub get_provider_type :GET Path('provider_type') Args(1) Does(Auth) AuthRole(ro-action) {
    my ($self, $c, $type_name) = @_;

    try {
        my $provider_type = $c->model("VennDB::Provider_Type")->find($type_name);
        if ($provider_type) {
            return $self->simple_ok_with_result($c, $provider_type->TO_JSON);
        }
        else {
            Venn::Exception::API::InvalidProviderType->throw({ providertype => $type_name });
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

## use critic

__PACKAGE__->meta->make_immutable;
