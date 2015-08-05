package Venn::Controller::API::v1::Audit;

=head1 NAME

Venn::Controller::API::v1::Audit - Audit table

=head1 DESCRIPTION

RESTful interface for the audit table.

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
use Scalar::Util qw(looks_like_number);

BEGIN {
    extends qw( Venn::Controller::API::v1 );
    with    qw( Venn::ControllerRole::API::Results );
}

use Venn::Types qw(:all);
use Venn::Exception qw(
    API::InvalidRequestID
);

=head1 METHODS

=head2 audit_base

Catalyst chained action base

=cut

sub audit_base :Chained('/') PathPart('api/v1/audit') CaptureArgs(0) { } ## no critic (RequireFinalReturn)

=head2 audit_known_pk

Captures the know request id and stores in $c->stash.

=cut

sub audit_known_pk :Chained('audit_base') PathPart('') CaptureArgs(1) {
    my ($self, $c, $pk) = @_;

    return $c->stash( request_id => $pk );
}

=head2 get_audit_all

REST GET /audit
    GET all audit items

    param rows   : (Int) number of rows to return, defaults to 100
    response 200 : (Array[AuditItem]) List of audit items

    schema AuditItem: {
      "required": ["http_method", "request_id", "request_payload", "response_code", "response_payload", "start_time", "uri_path", "user"],
      "properties": {
        "http_method": { "type": "string", "description": "method used for call", "example": "GET" },
        "request_id": { "type": "integer", "description": "request identifier", "example": "1" },
        "request_payload": { "type": "string", "description": "original request parameters, JSON structure" },
        "response_code": { "type": "integer", "description": "http response code", "example": "200" },
        "response_payload": { "type": "string", "description": "repsonse from Venn, JSON structure" },
        "start_time": { "type": "integer", "description": "timestamp of start", "example": "1396807033" },
        "uri_path": { "type": "string", "description": "original request path", "example": "api/v1/capacity" },
        "user": { "type": "string", "description": "remote user", "example": "venn@morgan" }
      }
    }

=cut

sub get_audit_all :GET Chained('audit_base') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c) = @_;

    try {
        my $rows = looks_like_number($c->req->params->{rows}) ? $c->req->params->{rows} : 100;
        $c->req->params->{rows} = $rows > 100 || $rows < 1 ? 100 : $rows;

        my @requests = $c->model('VennDB::Audit')
          ->search_with_query_params($c)
          ->as_hash
          ->all;
        $self->inflate_yaml_columns([qw/ response_payload request_payload /], \@requests);
        return $self->simple_ok_with_result($c, \@requests);
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

    return;
}

=head2 get_audit

REST GET /audit/$request_id
    GET a specific audit item

    param $request_id : (Int) audit request ID [required]
    response 200      : (AuditItem) audit item

=cut

sub get_audit :GET Chained('audit_known_pk') PathPart('') Args(0) Does(Auth) AuthRole(ro-action) {
    my ($self, $c ) = @_;
    my $request_id = $c->stash->{request_id};

    try {
        my $request = $c->model("VennDB::Audit")->find($request_id);
        if ($request) {
            return $self->simple_ok_with_result($c, $request->TO_JSON);
        }
        else {
            Venn::Exception::API::InvalidRequestID->throw({ request_id => $request_id });
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

    return;
}

__PACKAGE__->meta->make_immutable;
