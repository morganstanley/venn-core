package Venn::Controller::Root;

=head1 NAME

Venn::Controller::Root - Root Controller for Venn

=head1 DESCRIPTION

Root controller (/)

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

use Moose;
use namespace::autoclean;

use YAML::XS;
use JSON::XS;
use Data::Dumper;

BEGIN {
    extends 'Catalyst::Controller::ActionRole';
    #with 'Venn::Role::Logging';
}

__PACKAGE__->config(namespace => '');

## no critic (RequireFinalReturn,ProhibitBuiltinHomonyms)

=head1 METHODS

=head2 begin($c)

Initializer for every page

=cut

sub begin :Private {}

=head2 index($c)

The root page (/)

=cut

sub index :Path('/') :Args(0) {
    my ( $self, $c ) = @_;

    $c->redirect('/index.html');
}

=head2 swagger_index($c)

Swagger documentation root page redirect to index.html

=cut

sub swagger_index :Path('/swagger') :Args(0) {
    my ( $self, $c ) = @_;

    $c->redirect('/swagger/index.html');
}

=head2 whoami($c)

Returns the REMOTE_USER.

=cut

sub whoami :Local {
    my ( $self, $c ) = @_;

    $c->response->body($c->request->remote_user // 'unknown user');

    return;
}

=head2 status($c)

Returns status info for Venn.

=cut

sub status :Local {
    my ( $self, $c ) = @_;

    my $schema = $c->model('VennDB')->schema;

    my @connect_info = @{$schema->storage->connect_info // []};
    $connect_info[2] = "****" if defined $connect_info[2];

    my %status = (
        dbic_connected       => $schema->storage->connected,
        dbic_connect_info    => \@connect_info,
        dbic_storage_type    => $schema->storage_type,
        dbic_storage_type    => ref $schema->storage,
        venn_other_sources   => [ sort grep { !/^(?:A|C|J|P|M|NR)_/ } $schema->sources ],
        venn_misc_resources  => [ sort grep { /^M_/ } $schema->sources ],
        venn_providers       => [ sort grep { /^P_/ } $schema->sources ],
        venn_containers      => [ sort grep { /^C_/ } $schema->sources ],
        venn_attributes      => [ sort grep { /^A_/ } $schema->sources ],
        venn_named_resources => [ sort grep { /^NR_/ } $schema->sources ],
        venn_joins           => [ sort grep { /^J_/ } $schema->sources ],
        venn_sources         => [ sort $schema->sources ],
    );

    my $json = JSON::XS->new->ascii->pretty;

    $c->response->body("<pre>" . $json->encode(\%status) . "</pre>");

    return;
}

=head2 denied

403 Denied page

=cut

sub denied :Private {
    my ($self, $c) = @_;

    $c->res->status('403');
    $c->res->body('Denied!');
}

=head2 default($c)

Standard 404 error page

=cut

sub default :Path {
    my ( $self, $c ) = @_;

    $c->response->body('Requested URI not found');
    $c->response->status(404);
}

=head2 end

Attempt to render a view, if needed.

=cut

sub end : ActionClass('RenderView') {}

=head1 AUTHOR

Venn Engineering

=cut

__PACKAGE__->meta->make_immutable;
