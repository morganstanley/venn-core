package Venn::PlacementEngine::Request;

=head1 NAME

Venn::PlacementEngine::Request

=head1 DESCRIPTION

This class describes an incoming placement request for the Placement Engine.
It can be created automatically through the PlacementEngine->create() factory
sub. See the SYNOPSIS.

=head1 SYNOPSIS

    my %placement = (
        resources => {
            memory => 16,
            cpu => 1000,
            io => 20,
            disk => 62,
        },
        additional => {
            ports => 5,
        },
        attributes => {
            environment => 'dev',
            capabilities => {
                disk => [qw/ ssd /],
            },
        },
        location => {
            campus => 'ny',
            building => 'zy',
        },
        friendly => 'vm123',
        identifier => $UUID,
    );

    my $placement_engine = Venn::PlacementEngine->create('my_strategy', 'my_agt', $placement);

    my $placement_result = $placement_engine->place();

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
with qw( Venn::Role::SerializeAttrsToJSON );
use namespace::autoclean;

use Venn::Types;

use Log::Log4perl;
use Scalar::Util qw( reftype );
use Storable qw( dclone );

use MooseX::Types::Moose qw(Int Str HashRef Bool Maybe);
use MooseX::Types::Structured qw(Map);

use Venn::Types qw(:all);
use Venn::Exception qw(
    API::BadPlacementRequest
);

has 'assignmentgroup_type' => (
    is            => 'rw',
    isa           => Str, # TODO: type for this?
    required      => 1,
    documentation => 'AssignmentGroup Type',
);

has 'resources' => (
    is            => 'rw',
    isa           => HashRef[NonNegativeNum],
    init_arg      => undef,
    documentation => 'Requested resources',
);

has 'manual_placement' => (
    is            => 'rw',
    isa           => HashRef,
    init_arg      => undef,
    documentation => 'Manual placement definitions',
);

has 'force_placement' => (
    is            => 'rw',
    isa           => Bool,
    init_arg      => undef,
    documentation => 'Force placement without checking for available capacity. Intended for use with manual placement for admin.',
);

has 'attributes' => (
    is            => 'rw',
    isa           => HashRef,
    init_arg      => undef,
    documentation => 'Requested attributes',
);

has 'location' => (
    is            => 'rw',
    isa           => HashRef,
    init_arg      => undef,
    documentation => 'Requested resources',
);

has 'friendly' => (
    is            => 'rw',
    isa           => Maybe[Str],
    init_arg      => undef,
    documentation => 'Friendly lookup for the AssignmentGroup',
);

has 'commit' => (
    is            => 'rw',
    isa           => Bool,
    default       => 0,
    init_arg      => undef,
    documentation => 'Commit placement immediately',
);

has 'additional' => (
    is            => 'rw',
    isa           => HashRef,
    init_arg      => undef,
    documentation => 'Additional placement extensions (like port allocation)',
);

has 'identifier' => (
    is            => 'rw',
    isa           => Maybe[Str],
    init_arg      => undef,
    documentation => 'Identifier for the AssignmentGroup',
);

has 'instances' => (
    is            => 'rw',
    isa           => Int,
    init_arg      => undef,
    documentation => 'Number of instances to allocate (default 1)',
);

has '_raw_request' => (
    traits        => [qw( NoSerialize )],
    is            => 'ro',
    isa           => HashRef,
    init_arg      => 'raw_request',
    required      => 1,
    documentation => 'Definition of the Assignment Group Type',
);

class_has 'log' => (
    traits        => [qw( NoSerialize )],
    is            => 'ro',
    isa           => 'Log::Log4perl::Logger',
    init_arg      => undef,
    default       => sub { Log::Log4perl::get_logger(__PACKAGE__) },
    documentation => 'Logger',
);

=head1 METHODS

=head2 BUILD()

Initializes the attributes using data from the _raw_request hashref
passed in.

=cut

sub BUILD {
    my ($self) = @_;

    $self->_verify_resources();
    $self->_verify_attributes();

    $self->resources( $self->_raw_request->{resources} // {} );
    $self->attributes( $self->_parse_attributes() );
    $self->location( $self->_raw_request->{location} // {} );
    $self->friendly( $self->_raw_request->{friendly} );
    $self->identifier( $self->_raw_request->{identifier} );
    $self->manual_placement( $self->_raw_request->{manual_placement} // {} );
    $self->force_placement( $self->_raw_request->{force_placement} // 0 );
    $self->commit( $self->_raw_request->{commit} ? 1 : 0 );
    $self->additional( $self->_raw_request->{additional} // {} );
    $self->instances( $self->_raw_request->{instances} // 1 );

    return;
}

sub _parse_attributes {
    my ($self) = @_;

    my @resources = keys %{ $self->_raw_request->{resources} };

    my %parsed_attributes;

    my %request_attributes = %{ $self->_raw_request->{attributes} };

    for my $attribute (keys %request_attributes) {
        my $raw_value = $request_attributes{$attribute};
        next unless defined $raw_value;

        # capability => { cpu => [ 'vsi' ], ram => [ 'vsi' ]
        if (ref $raw_value eq 'HASH') {
            $self->_verify_resources($raw_value);
            $parsed_attributes{$attribute} = $raw_value;
        }
        # capability => [ 'vsi' ]
        else {
            for my $resource (@resources) {
                $parsed_attributes{$attribute}->{$resource} = ref $raw_value ? dclone $raw_value : $raw_value;
            }
        }
    }

    return \%parsed_attributes;
}

=head2 $self->_verify_resources()

Verifies all resources are actual providers.

=cut

sub _verify_resources {
    my ($self, $resources) = @_;
    $resources //= $self->_raw_request->{resources};

    my %provider_map = %{ Venn::Schema->provider_mapping };

    for my $resource (keys %$resources) {
        die "Not a resource: $resource" unless defined $provider_map{$resource};
    }

    return;
}

=head2 $self->_verify_attributes()

Verifies all attributes are actual attributes.

=cut

sub _verify_attributes {
    my ($self) = @_;

    my %attribute_map = %{ Venn::Schema->attribute_mapping };

    for my $attribute (keys %{ $self->_raw_request->{attributes} }) {
        die "Not an attribute: $attribute" unless defined $attribute_map{$attribute};
    }

    return;
}

__PACKAGE__->meta->make_immutable();
