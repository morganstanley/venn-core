package Venn::Role::Util;

=head1 NAME

Venn::Role::Util

=head1 DESCRIPTION

Utilities library

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

use Moose::Role;

use Hash::Merge;
use Scalar::Util 'reftype';

=head1 METHODS

=head2 $self->hash_replace($hash, $this, $that)

Replaces $this to $that by walking the hash

    return : (HashRef) Returns the modified hash

=cut

sub hash_replace {
    my ($self, $hash, $this, $that) = @_;

    if (ref $hash eq 'HASH') {
        for my $k (keys %$hash) {
            # substitution in value
            my $v = $hash->{$k};
            if (ref $v && reftype($v) eq "HASH") {
                $self->hash_replace($v, $this, $that);
            } elsif (ref $v && reftype($v) eq 'ARRAY') {
                @$v = map {$self->hash_replace($_, $this, $that)} @$v;
            } elsif (! ref $v) {
                $v =~ s/$this/$that/og;
            }

            my $new_hash = {};
            for my $k (keys %$hash) {
                # substitution in key
                (my $new_key = $k) =~ s/$this/$that/og;
                $new_hash->{$new_key} = $hash->{$k};
            }
            %$hash = %$new_hash; # replace old keys with new keys
        }
    }
    elsif (ref $hash && reftype($hash) eq 'ARRAY') {
        @$hash = map {$self->hash_replace($_, $this, $that)} @$hash;
    }
    elsif (!ref $hash) {
        $hash =~ s/$this/$that/og;
    }
    else {
        Carp::confess "Unknown reference encountered: ".ref($hash);
    }

    return $hash;
}

=head2 $self->hash_merge($hash1, $hash2 [, $precedence])

Simply merges the hashes, recursively, with left precedence

    return : (HashRef) Returns the merged hash

=cut

sub hash_merge {
    my ($self, $hash1, $hash2, $precedence ) = @_;
    $precedence //= 'LEFT_PRECEDENT';

    my $merger = Hash::Merge->new($precedence);

    return $merger->merge($hash1, $hash2);
}

1;
