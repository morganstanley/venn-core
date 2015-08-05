package Venn::Exception;

=head1 NAME

Venn::Exception

=head1 DESCRIPTION

Venn Exception base class

=head1 SYNOPSIS

use Venn::Exception qw(
    InvalidParams
    BadInput
    ...etc.
);

With TryCatch

try {
    Venn::Exception::MyError->throw({ message => "An error occurred!" });
}
catch {
    die $_ unless blessed $_ && $_->can('rethrow');

    if ($_->isa('Venn::Exception::MyError')) {
        # do stuff..
    }
    elsif ($_->isa('Venn::Exception::Other')) {
        # do other stuff...
    }
    elsif ($_->isa('Venn::Exception')) {
        # do other stuff...
    }
}

Without TryCatch

eval {
    Venn::Exception::MyError->throw({ message => "An error occurred!" });
};
my $e;
if ($e = Venn::Exception->caught('Aquilon')) {
    # do stuff...
}
elsif ($e = Venn::Exception->caught('Other')) {
    # do other stuff...
}
elsif ($e = Venn::Exception->caught()) {
    # do other stuff...
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

# TODO: implement :all tag if possible

use Moose;
use MooseX::ClassAttribute;
use namespace::autoclean;
extends 'Throwable::Error';

use Module::Pluggable
    sub_name    => '_plugins',
    search_path => [qw/ Venn::Exception /],
    require     => 1,
    inner       => 1,
;
use Import::Into;
use Module::Runtime qw( use_module );
use Data::OptList;
use Scalar::Util qw( blessed reftype );

class_has 'plugins' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    builder => '_plugins',
    lazy    => 1,
    documentation => 'List of all Exception classes',
);

has 'c' => (
    is  => 'ro',
    isa => 'Catalyst',
);

=head1 METHODS

=head2 import(@modules)

Imports all of the named exceptions:

    use Venn::Exception qw(
        InvalidParams
        BadInput
        ...etc.
    );

=cut

sub import {
    my ( $class, @modules ) = @_;

    my $target = caller;

    # this import should only be called for the base class, otherwise weird stuff happens
    return unless __PACKAGE__ eq 'Venn::Exception';

    # validate passed-in @modules array
    my @optlist = @{Data::OptList::mkopt(
        [ @modules ],
        { must_be => [qw( ARRAY HASH )] }
    )};
    for my $opt (@optlist) {
        my ($package, $package_opts) = @$opt;

        # Unless the package starts with a +, prepend our namespace
        for ($package) { s/^\+// or $_ = "Venn::Exception::$_" };

        my @args = ref $package_opts eq 'ARRAY'
                     ? @$package_opts
                     : ( ref $package_opts eq 'HASH' ? %$package_opts : () );

        #warn "Using $package, importing into $target with: " . join(" ", @args) . "\n";
        use_module($package)->import::into($target, @args);
    }

    return;
}

=head2 caught($class_name)

Tries to catch an Venn specific exception (Venn::Exception::$class_name).

e.g.
    if ($e = Venn::Exception->caught('Aquilon')) {
        // handle
    }

    param $class_name : (scalar) Name of the class minus the Venn::Exception prefix

=cut

sub caught {
    my ($self, $class_name) = @_;
    my $e = $@;

    return $e if defined $class_name && blessed $e && $e->isa("Venn::Exception::${class_name}");
    return $e if ! defined $class_name && blessed $e && $e->isa("Venn::Exception");

    return;
}

=head2 as_string_no_trace()

String representation of the exception without a stack trace.

    return : (scalar) String containing exception text

=cut

sub as_string_no_trace {
    my ($self) = @_;

    return $self->message;
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
