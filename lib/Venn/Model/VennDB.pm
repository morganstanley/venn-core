package Venn::Model::VennDB;

=head1 NAME

Venn::Model::VennDB

=head1 DESCRIPTION

Catalyst model that connects to the DBIC Schema, allowing you
to use $c->model('VennDB::NameOfDBICResultSource') to
access it.

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
use MooseX::NonMoose;
BEGIN { extends 'Catalyst::Model::DBIC::Schema' };

use Venn::Schema;

BEGIN {
    __PACKAGE__->config(
        schema_class => 'Venn::Schema',
        connect_info => Venn::Schema->generate_connect_info(),
    );
}

__PACKAGE__->meta->make_immutable;
