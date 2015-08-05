package Catalyst::Action::Serialize::YAMLXS;

=head1 NAME

Catalyst::Action::Serialize::YAMLXS

=head1 DESCRIPTION

YAML::XS Serializer for Catalyst

=head1 SYNOPSIS

    $c->stash->{rest} = {
        name  => 'Ryan',
        email => 'ryan@example.com',
    };

Generates:
    ---
    name: Ryan
    email: ryan@example.com

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

extends 'Catalyst::Action';
use YAML::XS;

=head1 METHODS

=head2 execute($controller, $c)

Serializes to the response body

=cut

sub execute {
    my ( $self, $controller, $c ) = @_;

    my $stash_key = (
            $controller->{serialize} ?
                $controller->{serialize}->{stash_key} :
                $controller->{stash_key}
        ) || 'rest';

    $c->response->output( $self->serialize($c, $c->stash->{$stash_key}) );

    return 1;
}

=head2 serialize($c, $data)

Encodes $data as YAML via YAML::XS

    param $data : (Any) Any structure that can be YAML encoded
    return      : (Str) YAML encoded $data

=cut

sub serialize {
    my ($self, $c, $data) = @_;

    return YAML::XS::Dump($data);
}

__PACKAGE__->meta->make_immutable;
