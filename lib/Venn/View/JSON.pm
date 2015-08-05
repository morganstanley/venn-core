package Venn::View::JSON;

=head1 NAME

Venn::View::JSON

=head1 DESCRIPTION

Catalyst View that serializes the output as JSON.

=head1 SYNOPSIS

    $c->stash->{rest} = {
        name  => 'Ryan',
        email => 'ryan@example.com',
    };

Generates:
    {name:'Ryan',email:'ryan@example.com'}

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
extends 'Catalyst::View::JSON';

use Scalar::Util qw( blessed );
use JSON::XS ();
use Data::Dumper;

=head1 METHODS

=head2 process($c, $stash_key)

=cut

sub process {
    my ( $self, $c, $stash_key ) = @_;
    $stash_key //= 'rest';

    my $output = eval { $self->serialize( $c, $c->stash->{$stash_key} ) };
    if ($@) {
        warn "Exception: $@\n";
        return $@;
    }

    $c->response->body( $output );
    return 1;
}

=head2 serialize($c, $data)

See L<Venn::View::encode_json>

=head2 encode_json($c, $data)

Encodes $data as JSON (optionally "pretty" json if stash->json_pretty is set.

    param $data : (Any) Any structure that can be JSON encoded
    return      : (Str) JSON encoded $data

=cut

*serialize = \&encode_json;
sub encode_json {
    my ($self, $c, $data) = @_;

    if (blessed $data && $data->can('TO_JSON')) {
        return $data->TO_JSON();
    }
    elsif ($c->stash->{json_pretty}) {
        return JSON::XS->new->ascii->pretty->allow_nonref->encode($data);
    }
    else {
        return JSON::XS->new->ascii->allow_nonref->encode($data);
    }
}


=head1 NAME

Venn::View::JSON - Catalyst JSON View for returning 'stash' data in JSON format.

=head1 DESCRIPTION

Catalyst JSON View, for returning items rendered to this view in JSON format.

=cut

1;
