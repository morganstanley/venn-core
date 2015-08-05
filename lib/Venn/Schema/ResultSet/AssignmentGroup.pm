package Venn::Schema::ResultSet::AssignmentGroup;

=head1 NAME

package Venn::Schema::ResultSet::AssignmentGroup

=head1 DESCRIPTION

Base resultset for AssignmentGroup

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

use 5.010;

use Moose;
use MooseX::NonMoose;
use namespace::autoclean;

extends 'Venn::SchemaBase::ResultSet';

=head1 METHODS

=head2 find_by_identifier($identifier)

Retrieve AssignmentGroup by identifier

    param $identifier   : (Str) Identifier for the assignment group
    return              : (ResultSet) AssignmentGroup

=cut

sub find_by_identifier {
    my ($self, $identifier) = @_;

    return $self->search({
        identifier => $identifier,
    })->single;
}

=head2 search_by_provider_primary_field($providertype, $providername)

Retrieve AssignmentGroups that have an assignment on the
given provider.

    param $providertype   : (Str) Providertype short name (eg. memory)
    param $providername   : (Str) Friendly name ("primary field")

    return                : (ResultSet) ResultSet selecting for assignmentgroup fields

=cut

sub search_by_provider_primary_field {
    my ($self, $providertype, $providername) = @_;

    my $primaryfield = Venn::Schema->provider_mapping->{$providertype}->{primary_field};
    my $ag_id_rs = $self->search(
        { "$providertype.$primaryfield" => $providername },
        {
            select   => [ qw/ me.assignmentgroup_id /],
            as       => [ qw/ assignmentgroup_id /],
            join     => { assignments => { provider => $providertype } },
            group_by => [ qw/ me.assignmentgroup_id /],
            having   => \[ 'sum(assignments.size) > 0' ],
        }
    );
    return $self->search_readonly({
        'me.assignmentgroup_id' => { -in => $ag_id_rs->as_query },
    }, {
        select => [qw/
            me.assignmentgroup_id
            me.assignmentgroup_type_name
            me.friendly
            me.identifier
            me.created
        /],
        as => [qw/
            assignmentgroup_id
            assignmentgroup_type_name
            friendly
            identifier
            created
        /],
    });
}

=head2 $rs->with_metadata()

Adds metadata to the ResultSet.

    return : (ResultSet) ResultSet with metadata column added

=cut

sub with_metadata {
    my ($self) = @_;

    return $self->search(undef, { '+columns' => [qw/ metadata /], });
}

=head2 $rs->with_assignments($join_providers)

Prefetches assignments (and optionally providers).

    return : (ResultSet) ResultSet with assignments and optionally providers

=cut

sub with_assignments {
    my ($self, $join_providers) = @_;

    my $prefetch_condition;
    if ($join_providers) {
        my $deployed_provider_mapping = $self->result_source->schema->deployed_mapping->{provider};
        my @prefetch;
        for my $provider (keys %$deployed_provider_mapping) {
            my $def = $deployed_provider_mapping->{$provider};
            if (ref $def->{relationships} && 'resources' ~~ @{$def->{relationships}}) {
                # include NR relation link into the result
                push @prefetch, { $provider => 'resources' };
            } else {
                push @prefetch, $provider;
            }
        }
        $prefetch_condition = { assignments => { provider => \@prefetch } };
    }
    else {
        $prefetch_condition = [qw/ assignments /];
    }

    return $self->search(undef, {
        prefetch => $prefetch_condition,
    });
}

=head2 $rs->flatten_assignment_data(\@records)

Flattens assignment data, removing empty providertype joins from prefetch_all_types.
Adds metadata to the active providertype.

    param \@records : (ArrayRef) Records containing assignments AND their providers
                                 (output from: $self->with_assignments(1))

=cut

sub flatten_assignment_data {
    my ($self, $records) = @_;
    $records //= [];

    for my $rec (@$records) {
        my $assignments = $rec->{assignments};
        for my $assignment (@$assignments) {
            my $provider = $assignment->{provider};
            for my $column (keys %$provider) {
                my $value = $provider->{$column};
                if (ref $value eq 'ARRAY' && scalar @$value == 0) {
                    delete $provider->{$column};
                }
                elsif (ref $value eq 'ARRAY' && defined Venn::Schema->provider_mapping->{$column}) {
                    $provider->{$column} = $value->[0];
                    my $provider_info = Venn::Schema->provider_mapping->{$column};
                    $provider->{$column}->{metadata} = {
                        primary_field   => $provider_info->{primary_field},
                        container_field => $provider_info->{container_field},
                    };
                }
            }
        }
    }
    return;
}


1;
