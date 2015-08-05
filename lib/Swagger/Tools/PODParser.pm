package Swagger::Tools::PODParser;
#-*- mode: CPerl;-*-

=head1 NAME

Swagger::Tools::PODParser

=head1 DESCRIPTION

Generates Swagger structure from POD fragments in a directory (Catalyst-compatible currently)

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

use Moo;

use PPI;
use Path::Class;
use Tie::IxHash;
use Hash::Merge qw(merge);
use Data::Walk;
use Scalar::Util qw(reftype);
use Storable qw(dclone);
use Scalar::Util qw(blessed);
use JSON::XS;
use Data::Dumper;

with qw( Swagger::Tools::Writer );

=head1 METHODS

=head2 pod_dir($dir)

Recursively processes $dir and extracts POD elements from REST endpoint definitions.

Definitions could include REST paths, URL parameters, query parameters, body
elements and return value schemas.

For definition examples, schemas, take a look into current API/v1 Controller files.

Returns a HASHref of data structure, which could be dumped as JSON.

=cut

sub pod_dir {
    my ($self, $dir, $opts) = @_;
    $opts //= {};

    Hash::Merge::set_behavior('RETAINMENT_PRECEDENT');
    Hash::Merge::set_clone_behavior(0);

    $dir = dir($dir) unless blessed($dir) && $dir->isa('Path::Class::Dir');

    $self->{_paths} = {};
    $dir->recurse( callback => sub { _process_file( $self, @_ ) } );

    # order Paths correctly
    tie(my %paths, 'Tie::IxHash');

    $paths{$_} = $self->_paths->{$_} for sort keys %{$self->_paths};
    $self->{structure}{paths} = \%paths;

    $self->{structure}{definitions} = $self->{definitions};

    $self->_check_refs();

    return $self->structure;
}

#
# _process_file($file)
#
# Called by pod_dir for every file to process
# Finds all REST <method> <path> [<section>] blocks, parses parameter, returns
# schemas.
# It populates $self->paths, $self->definitions.
#

sub _process_file { ## no critic Subroutines::ProhibitExcessComplexity
    my ($self, $file) = @_;

    return if $file->is_dir or $file !~ /\.pm$/;

    my $ppi = PPI::Document->new("$file", readonly => 1) || die "Can't load into PPI";

    for my $pod (@{$ppi->find('PPI::Token::Pod') // []}) {
        my $content = $pod->content;
        while ($content =~ m!^REST\s+(GET|POST|PUT|DELETE)\s+(/.+)\n+((?:  \s*.+\n+)+)!mg) {
            my ($method, $endpoint, $body) = ($1, $2, $3);

            my $tag;
            if (($tag) = $endpoint =~ /\s+<(\S+)>\s*$/) {
                $endpoint =~ s/\s+.+$//;
            }
            else {
                (undef,$tag) = split m|/|, $endpoint; # default tag is first URL part
            }

            $self->_debug("found $method endpoint $endpoint ($tag)");

            my $block = { tags => [$tag] };
            tie(my %params, 'Tie::IxHash');
            tie(my %responses, 'Tie::IxHash');

            my @lines = split /\n+/, $body;
            $block->{summary} = trim(shift @lines);
            $block->{summary} =~ s/\$(\w+)/{$1}/g;

            # get in-URL parameters
            while ($endpoint =~ m!/\$(\w+)!sg) {
                $params{$1} = {
                    name => $1,
                    in => 'path',
                };
            }

            # URL parameters
            while ($body =~ /^\s+param(?:s|eters?)?\s+\$?(\S+)\s*(.*)$/mg) {
                my ($name, $description) = ($1, $2);
                $description =~ s/^\s*:\s+//;

                my ($required, $type, $documentation) = $self->_description($description);

                my $specs = $type ? { @$type } : {};
                $specs->{required} = $required if $required;
                $specs->{description} = $documentation;

                $params{$name} //= { name => $name };
                $params{$name}{$_} //= $specs->{$_} for keys %$specs;
                $params{$name}{in} //= 'query'; # should be query parameter if not defined in URL
            }
            # Body parameters
            while ($body =~ /^\s+body\s*:\s*(.+)$/mg) {
                my ($description) = ($1);

                my ($required, $type, $documentation) = $self->_description($description);

                my $specs = $type ? { @$type } : {};
                $specs->{required} = $required if $required;
                $specs->{description} = $documentation if $documentation;
                $specs->{in} = $specs->{name} = 'body';

                $params{body} = $specs;
            }

            $block->{parameters} = [ values %params ];

            # response codes
            while ($body =~ /^\s+(?:response|returns?)\s+(\d+)\s*:\s*(.*)$/mg) {
                my ($code, $description) = ($1, $2);

                my ($required, $type, $documentation) = $self->_description($description, {autoschema => 1, wrap => 1});

                if ($type && !@$type) {
                    Carp::confess "ORIGINAL DESC: ".Data::Dumper::Dumper($description);
                }
                $responses{$code} = {
                    $type ? @$type : (),
                    $documentation ? (description => $documentation) : (),
                };
            }
            for my $code (keys %{$self->{responses}}) {
                $responses{$code} //=
#                    { schema => { '$ref' => "#/responses/$code" } }; # not supported :(
                    $self->{responses}{$code};
            }
            $block->{responses} = \%responses;

            # schema models
            while ($body =~ /(\s)+(?:schema)\s+(\w+):\n((?:\1\s+\S+\s*:\s*.+?\n)+)/sg) {
                my ($schema, $items) = ($2, $3);

                tie(my %items, 'Tie::IxHash');

                for my $item (split /\n/, $items) {
                    if ($item =~ /^\s+(\S+)\s*:\s*(.+)$/) {
                        my ($name, $desc) = ($1, $2);
                        my ($required, $type, $documentation) = $self->_description($desc);

                        $items{$name} = {
                            $type ? @$type : (),
                            $required ? (required => $required) : (),
                            $documentation ? (description => $documentation) : (),
                        };
                    }
                }

                die "Schema $schema redefined" if $self->{definitions}{$schema};
                $self->{definitions}{$schema}{properties} = \%items;
            }
            # JSON schema models
            while ($body =~ /(\s+)(?:schema)\s+(\w+):\s*({\s*\n.+?\n\1})\s*\n/sg) {
                my ($schema, $json) = ($2, $3);

                my $data = eval { decode_json($json) };
                if (my $err = $@) {
                    die "JSON schema parsing failed for $schema: $err\n$json\n";
                }

                die "Schema $schema redefined" if $self->{definitions}{$schema};
                $self->{definitions}{$schema} = $data;
            }

            $endpoint =~ s/\$(\w+)/{$1}/g; # convert parameter notation to Swagger syntax
            $self->{_paths}{$endpoint}{lc $method} = $block;
        }
    }

    return;
}

#
# _description($text, $options)
#
# Extracts documentation of an endpoint/parameter/return value from $text
# $options->{autoschema} = 1 allows schema auto-generation (like Array[Foobar] constructs)
# $options->{wrap} = 1 allows automatic { $ref => '#/definition/schemaname' } wrapping
#
# Returns ($bool_required, $data_type, $text_docs)
#

sub _description {
    my ($self, $text, $opt) = @_;
    $opt //= { autoschema => 0, wrap => 1};

    my ($required, $type);

    $text = trim($text);

    if ($text =~ s/\s*\[required\]\s*//) {
        $required = \1;
    }

    if (($type) = $text =~ /\(([\w\[\]]+)\)/) {
        $type = $self->_type($1, $opt);
        $text =~ s/\s*\(\w+\)\s*//;
    }

    return ($required, $type, $text);
}

#
# _type($type, $opt)
#
# Extracts the type of a parameter/return value
# $options are the same as _description() call.
#
# Returns an arrayref of Swagger-compatible type definition (either for
# primitive or user-defined complex types)
#

sub _type {
    my ($self, $type, $opt) = @_;
    $opt //= { autoschema => 0, wrap => 1};

    my ($result, $item, $items);
    if ($type =~ /^Array(?:Ref)?\[(\w+)\]/i) {
        $item = $1;
        $result = 'array';
        if (my $primitive = $self->_type_primitive($item, {wrap => 0})) {
            $items = ref($primitive) ? $primitive : { type => $primitive };
        } else {
            $items = { '$ref' => "#/definitions/$item" };
        }
    } else {
        $result = $self->_type_primitive($type);
    }

    if ($opt->{autoschema} && $item) {
        my $schema = "${item}s";
        # transform to array schema
        $self->{definitions}{$schema} //= {
            ref($result) ? %$result : (type => $result), ## no critic ValuesAndExpressions::ProhibitCommaSeparatedStatements
            $items ? (items => $items) : (),
        };

        return [
            $opt->{wrap} ?
              (schema => { '$ref' => "#/definitions/$schema" }) :
              ('$ref' => "#/definitions/$schema")
        ];
    } else {
        return [
            $result ? ref($result) ? %$result : (type => $result) : (),
            $items ? (items => $items) : (),
        ];
    }
}

#
# _type_primitive($type, $options)
#
# Extracts the primitive type declarations of parametes/return values
# $options are the same as _description() call.
#
# Returns either a string of primitive type or a hashref of
# reference to a complex type.
#

sub _type_primitive {
    my ($self, $type, $opt) = @_;
    $opt //= { wrap => 1 };

    if ($type =~ /^str/i) {
        return 'string';
    } elsif ($type =~ /^int/i) {
        return 'integer';
    } else {
        # let it be linked to it's definition
        return $opt->{wrap} ?
          { schema => { '$ref' => "#/definitions/$type" } } :
          { '$ref' => "#/definitions/$type" };
    }
}

# _check_refs()
#
# Checks whether all complex type definitions are present
# Throws an exception when an invalid/missing definition found.
#

sub _check_refs {
    my ($self) = @_;

    walk sub { _check_node($self, $_) }, $self;

    return;
}

# _check_node($node)
#
# Used by check_refs(), does the check of the currently walked node
#

## no critic Variables::ProhibitPackageVars
sub _check_node {
    my ($self, $_) = @_;

    if ((reftype($_) || '') eq 'HASH') {
        if (exists $_->{'$ref'}) {
            my $target = $_->{'$ref'};

            unless ($target =~ m!^\#/\w+/!) {
                die "Not top-level link: $target, from: ".Dumper($Data::Walk::container);
            }
            my (undef, $top, $schema) = split m!/!, $target;
            unless (defined($self->{$top}{$schema})) {
                die "Undefined link: $target, from: ".Dumper($Data::Walk::container);
            }
        }
    }
}
## use critic

=head1 AUTHOR

Venn Engineering

=cut

__PACKAGE__->meta->make_immutable;
