package Venn::ResultClass::HashRefInflatorFloatConvert;

=head1 NAME

Slightly modified to convert results from scientific notation into floats.

DBIx::Class::ResultClass::HashRefInflator - Get raw hashrefs from a resultset

=head1 SYNOPSIS

 use DBIx::Class::ResultClass::HashRefInflator;

 my $rs = $schema->resultset('CD');
 $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
 while (my $hashref = $rs->next) {
       ...
     }

  OR as an attribute:

 my $rs = $schema->resultset('CD')->search({}, {
       result_class => 'DBIx::Class::ResultClass::HashRefInflator',
     });
 while (my $hashref = $rs->next) {
       ...
     }

=head1 DESCRIPTION

DBIx::Class is faster than older ORMs like Class::DBI but it still isn't
designed primarily for speed. Sometimes you need to quickly retrieve the data
from a massive resultset, while skipping the creation of fancy result objects.
Specifying this class as a B<result_class> for a resultset will change C<< $rs->next >>
to return a plain data hash-ref (or a list of such hash-refs if B<< $rs->all >> is used).

There are two ways of applying this class to a resultset:

=over

=item *

Specify B<< $rs->result_class >> on a specific resultset to affect only that
resultset (and any chained off of it); or

=item *

Specify B<< __PACKAGE__->result_class >> on your source object to force all
uses of that result source to be inflated to hash-refs - this approach is not
recommended.

=back

Note: this module was mostly copied from DBIx::Class::ResultClass::HashRefInflator.

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

use strict;
use warnings;
use 5.010;

use Scalar::Util qw / reftype looks_like_number /;
#use Data::Types qw/ is_float is_int /;

no if $] >= 5.018, warnings => q{experimental::smartmatch};

# this class is designed for speed, sorry about the formatting
## no critic

##############
# NOTE
#
# Generally people use this to gain as much speed as possible. If a new &mk_hash is
# implemented, it should be benchmarked using the maint/benchmark_hashrefinflator.pl
# script (in addition to passing all tests of course :)

# This coderef is a simple recursive function
# Arguments: ($me, $prefetch, $is_root) from inflate_result() below

my $mk_hash;
$mk_hash = sub {

    my $hash = {

        # the main hash could be an undef if we are processing a skipped-over join
        $_[0] ? %{walkhash($_[0])} : (),

        # the second arg is a hash of arrays for each prefetched relation
        map { $_ => (

                    ref $_[1]->{$_}[0] eq 'ARRAY'
                        ? [ map { $mk_hash->( @$_ ) || () } @{$_[1]->{$_}} ]
                            : $mk_hash->( @{$_[1]->{$_}} )

                        ) } ($_[1] ? keys %{$_[1]} : ())
                    };

    ($_[2] || keys %$hash) ? $hash : undef;
};

=head1 METHODS

=head2 inflate_result

Inflates the result and prefetched data into a hash-ref (invoked by L<DBIx::Class::ResultSet>)
# HRI->inflate_result ($resultsource_instance, $main_data_hashref, $prefetch_data_hashref)

=cut

sub inflate_result {
    return $mk_hash->($_[2], $_[3], 'is_root');
}

=head2 walkhash(\%in, \%out)

Walk a hash

    param \%entry | \@entry | $entry : (HashRef|ArrayRef|Scalar) Incoming item to walk
    return                           : (HashRef|ArrayRef|Scalar) Float converted of same type

=cut

sub walkhash {
    my ($entry) = @_;

    my $type = reftype($entry) // "SCALAR";

    given ($type) {
        when (/^HASH$/) {
            for my $key (keys %$entry) {
                $entry->{$key} = walkhash($entry->{$key});
            }
        }
        when (/^ARRAY$/) {
            my @tmp;
            for my $arr (@$entry) {
                push @tmp, walkhash($arr);
            }
            $entry = \@tmp;
        }
        when (/^SCALAR$/) {
            if (looks_like_number($entry)) {
                return sprintf("%.2f", $entry);
            }
            else {
                return $entry;
            }
        }
    }
    return $entry;
}

=head1 CAVEATS

=over

=item *

This will not work for relationships that have been prefetched. Consider the
following:

 my $artist = $artitsts_rs->search({}, {prefetch => 'cds' })->first;

 my $cds = $artist->cds;
 $cds->result_class('DBIx::Class::ResultClass::HashRefInflator');
 my $first = $cds->first;

B<$first> will B<not> be a hashref, it will be a normal CD row since
HashRefInflator only affects resultsets at inflation time, and prefetch causes
relations to be inflated when the master B<$artist> row is inflated.

=item *

Column value inflation, e.g., using modules like
L<DBIx::Class::InflateColumn::DateTime>, is not performed.
The returned hash contains the raw database values.

=back

=cut

1;
