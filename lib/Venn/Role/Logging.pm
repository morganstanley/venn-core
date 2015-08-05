package Venn::Role::Logging;

=head1 NAME

Venn::Role::Logging - Logging Role

=head1 DESCRIPTION

Logging role that adds the Venn logger as the 'logger' attribute.

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

use Venn::Log::L4PWrapper;

class_has 'logger' => (
    is      => 'ro',
    isa     => 'Venn::Log::L4PWrapper',
    default => sub { Venn::Log::L4PWrapper->new(Log::Log4perl->get_logger(ref $_[0])) },
);

=head1 METHODS

=head2 log(opt $category)

Returns the logger with an optional alternative category

    param $category : (Str) Optional category
    return          : (Venn::Log::L4PWrapper) Logger

=cut

## no critic (ProhibitBuiltinHomonyms)
sub log {
    my ($self, $cat) = @_;

    # $self->log('::Something') => $self->log(My::Class::Something)
    # $self->log('.Something')  => $self->log(My::Class.Something)
    if (defined $cat && $cat =~ m/^(\.|::)/) {
        return Venn::Log::L4PWrapper->new(
            Log::Log4perl->get_logger(ref($self) . $cat)
        );
    }
    # $self->log('mycategory')
    elsif($cat) {
        return Venn::Log::L4PWrapper->new(
            Log::Log4perl->get_logger($cat)
        );
    }
    # $self->log
    else {
        return $self->logger;
    }
}
## use critic

1;
