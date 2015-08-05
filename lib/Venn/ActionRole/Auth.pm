package Venn::ActionRole::Auth;

=head1 NAME

Venn::ActionRole::Auth

=head1 DESCRIPTION

Authorization action class

=head1 SYNOPSIS

 package MyApp::Controller::Foo;
 use Moose;
 use namespace::autoclean;

 BEGIN { extends 'Catalyst::Controller' }

 sub foo
 :Local
 :Does(Auth)
 :AuthRole('ro-action')
 :AuthDetachTo(denied)
 {
     my ($self, $c) = @_;
     ...
 }

 sub denied :Private {
     my ($self, $c) = @_;

     $c->res->status('403');
     $c->res->body('Denied!');
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

use Moose::Role;
use MooseX::ClassAttribute;
use namespace::autoclean;

with 'Venn::Role::Logging';

sub BUILD { }

1;
