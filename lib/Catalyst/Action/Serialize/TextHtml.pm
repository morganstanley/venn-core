package Catalyst::Action::Serialize::TextHtml;

=head1 NAME

Catalyst::Action::Serialize::TextHtml

=head1 DESCRIPTION

Serialize to TextHtml

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

our $VERSION = 1.00;

use JSON::XS;

=head1 METHODS

=head2 execute($controller, $c)

Serializes the rest stash

=cut

sub execute {
    my ( $self, $controller, $c ) = @_;

    my $stash_key = (
        $controller->{serialize}
          ? $controller->{serialize}->{stash_key}
          : $controller->{stash_key}
    ) || 'rest';

    $c->response->output( $self->serialize($c->stash->{$stash_key}) );

    return 1;
}

=head2 serialize($data)

Serializes using JSON::XS

=cut

sub serialize {
    my $self = shift;
    my $data = shift;

    return sprintf "<pre>%s</pre>", JSON::XS->new->ascii->pretty->allow_nonref->encode($data);
}

__PACKAGE__->meta->make_immutable;
