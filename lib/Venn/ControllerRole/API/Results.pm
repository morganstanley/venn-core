package Venn::ControllerRole::API::Results;

=head1 NAME

Venn::ControllerRole::API::Results - Methods to help with returning results

=head1 DESCRIPTION

Methods to help with returning results.

=head1 SYNOPSIS

  with 'Venn::ControllerRole::API::Results';

  sub echo :Args(1) GET {
      my ($self, $c, $arg) = @_;
      return $self->simple_ok_with_result($c, $arg);
  }

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

use Moose::Role;

use YAML::XS;
use Scalar::Util qw( reftype );

no if $] >= 5.018, warnings => q{experimental::smartmatch};

=head1 METHODS

=head2 $self->simple_created($c, $result, opt $message, opt @message_args)

Returns a successful 201 Created with a result and optional message.

=cut

sub simple_created {
    my ($self, $c, $result, $format, @args) = @_;

    my $entity =
      reftype $result eq 'ARRAY'
      ? $result
      : reftype $result eq 'HASH'
      ? $result
      : [ $result ]
      ;

    $c->log->debugf("[201] Created: %s", sprintf($format // '', @args));

    return $self->status_created(
        $c,
        location => $c->req->uri,
        entity => $entity,
    );
}

=head2 $self->simple_not_found($c, $error, $message, opt @message_args)

Returns a 404 with an error

=cut

sub simple_not_found {
    my ($self, $c, $format, @args) = @_;
    $format //= '';

    my $msg = sprintf $format, @args;
    $c->log->debugf("[404] Not found: %s", $msg);

    return $self->status_not_found(
        $c,
        entity => {
            error   => $msg,
        },
    );
}

=head2 $self->simple_unauthorized($c, $error_format, opt @error_args)

Returns a 401 Unauthorized with an error

=cut

sub simple_unauthorized {
    my ($self, $c, $error_format, @args) = @_;

    my %entity;

    $entity{error} = sprintf($error_format, @args) if defined $error_format;

    $c->log->debugf("[401] Unauthorized: %s", $entity{error} // '');

    return $self->status_unauthorized(
        $c,
        entity => \%entity,
    );
}

=head2 $self->simple_conflict($c, $error_format, opt @error_args)

Returns a 409 Conflict with an error

=cut

sub simple_conflict {
    my ($self, $c, $error_format, @args) = @_;

    my %entity;

    $entity{error} = sprintf($error_format, @args) if defined $error_format;

    $c->log->debugf("[409] Conflict: %s", $entity{error} // '');

    return $self->status_conflict(
        $c,
        entity => \%entity,
    );
}

=head2 $self->simple_ok($c, $result, $message_format, @sprintf_args)

=head2 $self->simple_ok_with_result($c, $result, $message_format, @sprintf_args)

Returns a 200 OK with a result and optional message

=cut

*simple_ok = \&simple_ok_with_result;
sub simple_ok_with_result {
    my ($self, $c, $result, $format, @args) = @_;

    my $entity =
      reftype $result eq 'ARRAY'
      ? $result
      : reftype $result eq 'HASH'
      ? $result
      : [ $result ]
    ;
    my $message = defined($format) ? sprintf($format, @args) : '';
    $entity->{message} = sprintf($format, @args) if $message and reftype($result) eq 'HASH';

    $c->log->debugf("[200] OK: %s", $message // '');

    return $self->status_ok(
        $c,
        entity => $entity,
    );
}

=head2 $self->simple_ok_without_result($c, $message_format, @sprintf_args)

Returns a 200 OK with an optional message

=cut

sub simple_ok_without_result {
    my ($self, $c, $format, @args) = @_;
    $format //= '';

    my $msg = sprintf $format, @args;
    $c->log->debugf("[200] OK: %s", $msg);

    return $self->status_ok(
        $c,
        entity => {
            message => $format ? sprintf($format, @args) : 'OK',
        },
    );
}

=head2 $self->simple_forbidden($c, $error)

Return a 403 with an error message.

=cut

sub simple_forbidden {
    my ($self, $c, $format, @args) = @_;
    $format //= '';

    my $msg = sprintf $format, @args;
    $c->log->debugf("[403] Forbidden: %s", $msg);

    return $self->status_forbidden(
        $c,
        entity => {
            error => $msg,
        },
    );
}

=head2 $self->simple_bad_request($c, $error_format, @sprintf_args)

Return a 400 with an error message.

=cut

sub simple_bad_request {
    my ($self, $c, $format, @args) = @_;
    $format //= '';

    my $msg = sprintf $format, @args;
    $c->log->debugf("[400] Bad Request: %s", $msg);

    return $self->status_bad_request(
        $c,
        entity => {
            error => $msg,
        },
    );
}

=head2 $self->simple_internal_server_error($c, $error_format, @sprintf_args)

Return a 500 with an error message.

=cut

sub simple_internal_server_error {
    my ($self, $c, $format, @args) = @_;

    my $msg = sprintf $format, @args;
    $c->log->debugf("[500] Internal Server Error: %s", $msg);

    return $self->status_internal_server_error(
        $c,
        entity => {
            error => $msg,
        },
    );
}

=head2 $self->status_internal_server_error($c, @args)

Returns 500: Internal Server Error

=cut

sub status_internal_server_error {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, {
        entity => 1,
    });

    $c->response->status(500);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_not_implemented($c, @args)

Returns 501: Not Implemented

=cut

sub status_not_implemented {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(501);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_bad_request($c, @args)

Override parent status_bad_request to take an "entity" to serialize

=cut

sub status_bad_request {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(400);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_forbidden($c, @args)

Returns a 403 Forbidden and takes an "entity" to serialize

=cut

sub status_forbidden {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(403);
    $self->_set_entity($c, $p{'entity'});
    return 1;
}

=head2 $self->status_conflict($c, @args)

Returns a 409 Conflict and takes an "entity" to serialize

=cut

sub status_conflict {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(409);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_unauthorized($c, @args)

Returns a 401 Unauthorized and takes an "entity" to serialize

=cut

sub status_unauthorized {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(401);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_accepted($c, @args)

Override parent status_accepted to take an "entity" to serialize

=cut

sub status_accepted {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(202);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_not_found($c, @args)

Override parent status_not_found to take an "entity" to serialize

=cut

sub status_not_found {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(404);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->status_gone($c, @args)

Override parent status_gone to take an "entity" to serialize

=cut

sub status_gone {
    my ($self, $c, @args) = @_;
    my %p = Params::Validate::validate(@args, { entity => 1 });

    $c->response->status(410);
    $self->_set_entity($c, $p{entity});
    return 1;
}

=head2 $self->serialize_types($c, opt $prefix)

Serialize the types of providers, attributes, containers.

    param $c      : (catalyst context) Catalyst $c
    param $prefix : (optional string) Class prefix

=cut

sub serialize_types {
    my ($self, $c, $prefix) = @_;
    $prefix .= '_';

    my @sources = grep { /^$prefix/ } $c->model("VennDB::Provider")->result_source->schema->sources;
    my @types;
    for my $type (@sources) {
        ( my $api_name = $type ) =~ s/^$prefix//;
        $api_name = lc $api_name;

        my $rsrc = $c->model("VennDB::${type}")->result_source;
        my %column_info = %{ $rsrc->columns_info };
        my %column_info_sanitized;
        for my $col (keys %column_info) {
            my $info = $column_info{$col};
            for my $attr (keys %$info) {
                my $val = $info->{$attr};
                my $reftype = reftype $val // 'undef';
                if ($reftype eq 'SCALAR') {
                    $column_info_sanitized{$col}{$attr} = $$val;
                }
                elsif ($reftype eq 'CODE') {
                    $column_info_sanitized{$col}{$attr} = 'CODE';
                }
                elsif ( $reftype ~~ [qw( undef ARRAY HASH )] ) {
                    $column_info_sanitized{$col}{$attr} = $val;
                }
            }
        }

        push @types, {
            class                => $type,
            api_name             => $api_name,
            columns              => \%column_info_sanitized,
            primary_field        => "Venn::Schema::Result::${type}"->primary_field,
            display_name         => "Venn::Schema::Result::${type}"->display_name,
        };
    }

    return \@types;
}

=head2 $self->inflate_yaml_columns(\@columns, \@records)

Takes a hashref inflated record or set of records and inflates YAML column(s).

    param \@columns : (ArrayRef) Columns to YAML inflate
    param \@records : (ArrayRef) Records to inflate
    return          : (ArrayRef)

=cut

sub inflate_yaml_columns {
    my ($self, $columns, $records) = @_;
    $columns //= [];
    $records //= [];

    for my $record (@$records) {
        for my $column (@$columns) {
            $record->{$column} = YAML::XS::Load($record->{$column}) if defined $record->{$column};
        }
    }
    return $records;
}

1;
