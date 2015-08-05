package Venn::PlacementEngine::Strategy::BiggestOutlier;

=head1 NAME

Venn::PlacementEngine::Strategy::BiggestOutlier

=head1 DESCRIPTION

Biggest Outlier Strategy

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

# TODO: Write description

use v5.14;
use Moose;
use MooseX::ClassAttribute;
extends 'Venn::PlacementEngine::Strategy';
with qw(
    Venn::Role::Logging
    Venn::PlacementEngine::StrategyInterface
);
use namespace::autoclean;

use Data::Dumper;
use Scalar::Util qw(reftype);

Venn::PlacementEngine::Strategy->helpers(qw(
    AvgResources
    JoinCorrelateFilter
));

=head1 METHODS

=head2 name()

Name of the strategy

    return : (Str) Strategy name

=cut

sub name { return "biggest_outlier"; }

=head2 place()

Places using the Biggest Outlier placement strategy.

    return : (ResultSet) Placement ResultSet

=cut

augment 'place' => sub {
    my ($self) = @_;

    $self->log->debug("Placing using the biggest outlier strategy");

    my $join_correlate_filter = $self->join_correlate_filter();

    # take an average for all resource_avgs
    my $resavg = $self->avg_resources($self->request->assignmentgroup_type);

    # calculate % for each resource
    my %sort_order;
    for my $resource (keys %{$self->request->{resources}}) {
        my $quantity = $self->request->{resources}->{$resource};
        next if $resource ~~ @{$self->definition->{skip_in_ordering}};
        next if $quantity == 0; # most likely a migrate and place.. but static resources shouldn't be considered
        my $avg = $resavg->{"${resource}_avg"};
        $self->result->placement_info->{assigned_avg_quantity}->{$resource} = $avg;
        next unless (defined $avg && $avg != 0); ## no critic (ProhibitNegativeExpressionsInUnlessAndUntilConditions)
        $sort_order{percentages}{$resource}    = ($quantity - $avg) / (($quantity+$avg)/2);
        $sort_order{abs_percentages}{$resource} = abs($quantity - $avg) / (($quantity+$avg)/2);
    }

    # sort sort_order descending
    my $absperc = $sort_order{abs_percentages};
    for my $key (sort { $absperc->{$b} cmp $absperc->{$a} } keys %$absperc) {
        my $order = $sort_order{percentages}{$key} > 0 ? '-desc' : '-asc';
        push @{$sort_order{sql_order}}, { $order => $key . "_unassigned" };
    }

    $self->result->placement_info->{sorting} = \%sort_order;

    my %attrs = (
        order_by => $sort_order{sql_order},
    );
    $attrs{rows} = 1 unless $self->all_rows;

    $self->log->debugf("Attributes: %s", Dumper(\%attrs));

    return $join_correlate_filter->search(undef, \%attrs);
};

#c2013 Josh Arenberg, Ryan Kupfer, and mathsisfun.com

1;
