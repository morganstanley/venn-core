package Venn::Schema::ResultSet::Provider;

=head1 NAME

Venn::Schema::ResultSet::Provider - Provider ResultSet

=head1 DESCRIPTION

Provider ResultSet base class with various helpers

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
use namespace::autoclean;

extends 'Venn::SchemaBase::ResultSet';
with 'Venn::Role::Logging';

use Data::Dumper;
use Scalar::Util qw( looks_like_number );
use Venn::Schema::ResultClass::ProviderHashRefInflator;

__PACKAGE__->load_components(qw/ Helper::ResultSet::CorrelateRelationship /);

=head1 METHODS

=head2 with_provider_id($provider_id)

Searches for a provider with a specific provider_id

    param $provider_id : (Int) ID of the provider
    return             : (ResultSet) ResultSet with the where condition added

=cut

sub with_provider_id {
    my ($self, $provider_id) = @_;

    return $self->search({ 'me.provider_id' => $provider_id });
}

=head2 prefetch_all_types

    return : (ResultSet) ResultSet with all provider types prefetched

=cut

sub prefetch_all_types {
    my ($self) = @_;

    return $self->prefetch([ keys %{ Venn::Schema->provider_mapping } ]);
}

=head2 with_assignments()

Prefetches all assignments.

    return : (ResultSet) ResultSet with the assignments prefetch

=cut

sub with_assignments {
    my ($self) = @_;

    return $self->prefetch('assignments');
}

=head2 as_flat_hash()

Returns the ResultSet as a hash.

TODO: This needs extra work. In theory it should:
    - ArrayRef: join(',' , \@arr)
    - HashRef:  join(',' , map { sprintf "%s: %s", $_, $hash->{$_} } keys \%hash

    return : (ResultSet) The ResultSet as a hash

=cut

sub as_flat_hash {
    my ($self) = @_;

    $self->result_class('Venn::ResultClass::ProviderHashRefInflator');

    return $self;
}

=head2 average_assigned

  Returns the average size of an assignment for this provider, per assignment group.
  Takes a number of optional params in the $args hashref.

  param $args : (HashRef) Takes a number of args that limit the providers included in the average.
                             The following keys are supported:
                                (Str)           providertype : the shortname of the providertype to select
                                (Int - Epoch)   available    : minimum available date to be included ( defaults to now )
                                (Str)           statename    : include providers in this state ( defaults to active )
                                (HashRef[Str])  location_hash: hashref of locations ( must include the container and value )
  param $resource : (String) Resource name
  param $attributes : (HashRef) Attribute => Resource mapping (e.g. environment => 'dev')

=cut

sub average_assigned {
    my ($self, $args, $resource, $attributes) = @_;
    $args //= {};
    $attributes //= {};

    my (%where, @join);

    $where{'me.providertype_name'} = $args->{providertype} if $args->{providertype};
    $where{'me.available_date'}    = { '<=' => $args->{available} || time() };
    $where{'me.state_name'}        = $args->{statename} || 'active';

    my %attrmap = %{ Venn::Schema->attribute_mapping };
    for my $attribute (keys %attrmap) {
        next unless defined $attributes->{$attribute}->{$resource};

        my $accessor      = "provider_" . $attrmap{$attribute}{plural};
        my $primary_field = $attrmap{$attribute}{primary_field};

        $where{"$accessor.$primary_field"} = $attributes->{$attribute}->{$resource};

        push @join, $accessor;
    }

    %where = ( %where, %{$args->{location_hash}} ) if $args->{location_hash};

    return $self->search( \%where, {
        select => [{ avg => 'assignments.size' }],
        as     => [ 'avg_assigned_size' ],
        #group_by => 'assignments.assignmentgroup_id',
        join   => [ 'assignments', @join, $args->{join} ],
    });
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
