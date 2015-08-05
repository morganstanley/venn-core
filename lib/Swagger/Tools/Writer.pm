package Swagger::Tools::Writer;
#-*- mode: CPerl;-*-

=head1 NAME

Swagger::Tools::Writer

=head1 DESCRIPTION

Swagger-compatible JSON generator engine skeleton

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
use warnings;

use Moo::Role;

has 'debug' => ( is => 'rw', default => sub { 0 }, documentation => 'Enable debug print output' );

has 'base_path' => ( is => 'ro', required => 1, documentation => 'URL base path, like api/vi' );
has 'info'      => ( is => 'ro', documentation => 'Swagger info block' );
has 'schemes'   => ( is => 'ro', default => sub { ['http'] }, documentation => 'API access schemas' );
has 'consumes'  => ( is => 'ro', default => sub { ['application/json'] } );
has 'produces'  => ( is => 'ro', default => sub { ['application/json'] } );
has 'responses' => ( is => 'ro', default => sub { {
    '500' => { description => 'Unexpected error' },
} } );

has 'swagger_version'   => ( is => 'ro', default => sub { '2.0' } );

has 'structure' => (
    is => 'ro',
    default => sub { {} },
    documentation => 'Holds the whole Swagger-compatible API document structure',
);
has '_paths' => (
    is => 'ro',
    documentation => 'Internal representation of URL paths',
);

=head1 METHODS

=head2 BUILD()

Sets defaults for object.

=cut

sub BUILD {
    my ($self) = @_;

    my $s = $self->{structure};

    $s->{paths} //= {};
    $s->{definitions} //= {};

    for my $attr (qw(info schemes consumes produces responses)) {
        $s->{$attr} //= $self->$attr;
    }
    $s->{basePath} //= $self->base_path;
    $s->{swagger} = $self->swagger_version;

    return;
}

=head2 $self->_debug(<$msg|\%hash|\@array>, [<$msg|\%hash|\@array>, ...])

Concatenates parameters (dumps references) and warns it out when $self->debug
is enabled.

=cut

sub _debug { ## no critic Subroutines::ProhibitUnusedPrivateSubroutines
    my ($self, @args) = @_;

    return unless $self->debug;

    my $msg = '';
    for (@args) {
        $msg .= ref $_ ? Dumper($_) : $_;
    }
    warn "$msg\n";

    return;
}

=head2 $self->trim($string)

Removes prefix and postfix whitespaces from string.

=cut

sub trim {
    my $string = shift;

    $string =~ s/^\s+|\s+$//g;

    return $string;
}

=head1 AUTHOR

Venn Engineering

=cut

__PACKAGE__->meta->make_immutable;
