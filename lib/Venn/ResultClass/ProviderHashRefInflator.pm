package Venn::ResultClass::ProviderHashRefInflator;

=head1 NAME

Venn::ResultClass::ProviderHashRefInflator - Get raw provider hashrefs from a resultset

=head1 SYNOPSIS

 use Venn::ResultClass::ProviderHashRefInflator;

 my $rs = $schema->resultset('CD');
 $rs->result_class('Venn::ResultClass::ProviderHashRefInflator');
 while (my $hashref = $rs->next) {
   ...
 }

  OR as an attribute:

 my $rs = $schema->resultset('CD')->search({}, {
   result_class => 'Venn::ResultClass::ProviderHashRefInflator',
 });
 while (my $hashref = $rs->next) {
   ...
 }

=head1 DESCRIPTION

Similar to HashRefInflator, convert a Provider result into a flat hash while intelligently
renaming relationship columns to their proxy accessor names and flattening the hash.

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

use v5.14;
use warnings;

use Data::Dumper;

# this class is designed for speed, sorry about the formatting
## no critic

my $mk_hash;
$mk_hash = sub {
    # Arguments: ($me, $prefetch, $is_root) from inflate_result() below

    my $hash = {
        # the main hash could be an undef if we are processing a skipped-over join
        $_[0]
            ? %{$_[0]}
            : (),

        # the second arg is a hash of arrays for each prefetched relation
        map {
            ref $_[1]->{$_}[0] eq 'ARRAY' # multi rel or not?
                ? (
                      $_ => [
                          map {
                              $mk_hash->(@$_) || ()
                          } @{$_[1]->{$_}}
                      ]
                  )
                : (
                      $_ => $mk_hash->( @{$_[1]->{$_}} )
                  )
        } ( $_[1] ? ( keys %{$_[1]} ) : () )
    };

  # if there is at least one defined column *OR* we are at the root of
  # the resultset - consider the result real (and not an emtpy has_many
  # rel containing one empty hashref)
  # an empty arrayref is an empty multi-sub-prefetch - don't consider
  # those either
    return $hash if $_[2];

    for (values %$hash) {
        return $hash if ( defined $_ && ( ref $_ ne 'ARRAY' || scalar @$_ ) );
    }

    return undef;       ## no critic(ProhibitExplicitReturnUndef)
};

=head1 METHODS


=head2 inflate_result

Inflates the result and prefetched data into a hash-ref (invoked by L<DBIx::Class::ResultSet>)

=cut

##################################################################################
# inflate_result is invoked as:
# HRI->inflate_result ($resultsource_instance, $main_data_hashref, $prefetch_data_hashref)
sub inflate_result {
    my $hash = $mk_hash->($_[2], $_[3], 'is_root');

    my $rel_name;
    my $rel_info = {};

    for my $rel (keys %{$_[3]}) {
        if (! defined $hash->{$rel} || (ref $hash->{$rel} eq 'ARRAY' && scalar(@{$hash->{$rel}}) < 1)) {
            # unset undefined prefetches
            delete $hash->{$rel};
            next;
        }
        else {
            $rel_name = $rel;
            $rel_info = delete $hash->{$rel};
            $rel_info = $rel_info->[0]; # there's only one valid relationship
        }

        # traverse prefetch, renaming columns to their proxy accessor names
        for my $proxy (@{$_[1]->relationship_info($rel)->{attrs}->{proxy}}) {
            next unless ref $proxy eq 'HASH';
            for my $proxy_name (keys %$proxy) {
                my $original_name = $proxy->{$proxy_name};
                if (exists $hash->{$rel}->{$original_name}) {
                    $hash->{$rel}->{$proxy_name} = delete $hash->{$rel}->{$original_name};
                }
            }
        }
    }

    my $flathash = {};
    flatten($hash, $flathash);
    flatten($rel_info, $flathash);

    if (defined $rel_name) {
        my $source = Venn::Schema->provider_mapping->{$rel_name}->{source};
        if (defined $source) {
            my $class = "Venn::Schema::Result::${source}";
            $flathash->{metadata}->{primary_field}     = $class->primary_field;
            $flathash->{metadata}->{container_field}   = $class->container_field;
            $flathash->{metadata}->{providertype_name} = $rel_name;
        }
    }

    return $flathash;
}

=head2 flatten(\%in, \%out)

Flattens a hash.

    param \%in  : (HashRef) Incoming hashref
    param \%out : (HashRef) Result hashref


=cut

sub flatten {
    my ($in, $out) = @_;
    for my $key (keys %$in) {
        my $value = $in->{$key};
        if ( defined $value && ref $value eq 'HASH' ) {
            flatten($value, $out);
        }
        else {
            $out->{$key} = $value;
        }
    }
}

## use critic


=head1 CAVEATS

=over

=item *

This will not work for relationships that have been prefetched. Consider the
following:

 my $artist = $artitsts_rs->search({}, {prefetch => 'cds' })->first;

 my $cds = $artist->cds;
 $cds->result_class('Venn::ResultClass::ProviderHashRefInflator');
 my $first = $cds->first;

B<$first> will B<not> be a hashref, it will be a normal CD row since
ProviderHashRefInflator only affects resultsets at inflation time, and prefetch causes
relations to be inflated when the master B<$artist> row is inflated.

=item *

Column value inflation, e.g., using modules like
L<DBIx::Class::InflateColumn::DateTime>, is not performed.
The returned hash contains the raw database values.

=back

=cut

1;
