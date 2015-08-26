package Venn::PlacementEngine::Helper::Ports;

=head1 NAME

Venn::PlacementEngine::Helper::Ports;

=head1 DESCRIPTION

Assigns "named resource" ports for Subproviders.
Used as a pre/postprocess helper by port providers.

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
use IntervalTree;
use Storable qw(dclone);
use List::Util qw(max);

use Venn::Exception qw(Placement::PortsExhausted);

no if $] >= 5.018, warnings => q{experimental::smartmatch};

requires qw(log definition schema request
            placement_location placement_candidates);

=head1 METHODS

=head2 $self->place()

Places additional port allocation request onto a hostgroup.
It's called as a Placementengine preprocess handler.

It uses $self->request->additional->{ports} hashref as input.
eg.:
    {
        ports => 3,      # number of ports to be allocated
        min   => 1024,   # lowest possible port
        max   => 32000,  # highest possible port
        sequential => 1, # allocate adjacent ports
        samerange => 'container', # allocate the same portrange within
                                  # host of the specified scope: undef
                                  # hostgroup, building, continent, global
    }

It modifies $self->placement_location, enriching it with port allocation
details, or if allocation fails, raises an exception.
Port allocation groups are arrayrefs of hashrefs, possibly representing
different ranges when non-sequential allocation specified (see below).
eg.:
    {
         'container' => $hostgroup_name,
         'ports' => {
            'zy1_host2' => [
                {
                   'num' => 3,
                   'start' => 1074
                },
            ],
            'zy1_host1' => [
                {
                   'num' => 1,
                   'start' => 1024
                },
                {
                   'num' => 2,
                   'start' => 1074
                },
            ],
            'zy1_host3' => [
                {
                   'num' => 3,
                   'start' => 1074
                }
            ],
        }
    }

Abstract algorithm:
  -> iterates over all $self->placement_candidates (uses the hostname)
     -> selects a host from the hostgroup which needs to-be-allocated ports
        -> calls $self->_get_portrange to get an available port range for this
           host and calls $self->_store_allocation to store it into
           $self->port_response
        -> $self->_store_allocation will either store the range for the current
           host (no 'sameports' specified), could store it for all hosts in the
           hostgroup ('sameports' specified), or refuse storing when a conflict
           found
        -> if all hosts are satisfied, sets result in $self->placement_location
           and finishes outer loop

=cut

has port_request     => ( is => 'rw', isa => 'HashRef' );
has port_response    => ( is => 'rw', isa => 'HashRef' );

sub place {
    my ($self) = @_;

    my $agt = $self->{strategy}{definition};
    my $container = $self->schema->resultset($agt->{ports}{container_class});

    return unless $self->request->additional->{ports}; # no ports requested

    my $entity_primary_field = $agt->{ports}{entity_primary_field} // 'hostname';

    $self->port_request(dclone($self->request->additional->{ports}));
    # set defaults
    $self->port_request->{min} //= 1024;
    $self->port_request->{max} //= 65535;
    $self->port_request->{sequential} //= 0;

 CANDIDATE:
    for my $candidate_idx (0..scalar(@{$self->placement_candidates})) {
        my $candidate = $self->placement_candidates->[$candidate_idx];
        $self->placement_location($candidate) unless $candidate_idx == 0;

        $self->port_request->{host} = $self->schema->resultset($agt->{ports}{entity_class})
          ->single({ $entity_primary_field => $candidate->{$entity_primary_field} });
        my $entity_to_container_function = $agt->{ports}{entity_to_container_function};
        $self->port_request->{container} = $self->port_request->{host}->$entity_to_container_function();
        my $entities_of_container_function = $agt->{ports}{entities_of_container_function};
        $self->port_request->{hosts} = [ $self->port_request->{host}->$entities_of_container_function() ];

        # initialize an empty response with all hosts in hostgroup
        $self->port_response({ map { ## no critic (BuiltinFunctions::ProhibitVoidMap)
            $_ => {
                ports       => [],
                allocated   => 0,
            } } @{$self->port_request->{hosts}} });

        while (my $current_host = $self->_select_host()) {
            my $min_range = $self->port_request->{sequential} ?
                               $self->port_request->{ports} : 1;
            my $max_range = $self->port_request->{ports} - $self->port_response->{$current_host}{allocated};
            my $range = $self->_get_portrange($current_host, $min_range, $max_range);

            next CANDIDATE unless $range; # one of the hosts exhausted, next candidate!

            $self->_store_allocation($current_host, $range);
        }

        $candidate->{$agt->{ports}{container}} = $self->port_request->{host}->$entity_to_container_function;
        $candidate->{ports} = {
            map {$_ => $self->port_response->{$_}{ports}} keys %{$self->port_response}
        };

        last CANDIDATE;
    }

    unless ($self->placement_location->{$agt->{ports}{container}}) {
        die "Ports placement failed";
    }

    return;
}

=head2 $self->_select_host()

Selects the next host for placement.

Returns the to-be-allocated hostname or undef if all hosts has allocated range
already.

=cut

sub _select_host {
    my ($self) = @_;

    for my $host (keys %{$self->port_response}) {
        my $current = $self->port_response->{$host};
        return $host if $current->{allocated} < $self->port_request->{ports};
    }

    return;
}

=head2 $self->finalize()

Creates database entries for port allocation using P_Ports_Farm_Host and
NR_Farm_Port Result classes and creates the appropriate Assignment entries.
It's called as a Placementengine postprocess handler.

Processes $self->placement_location->{ports} hashref.

=cut

sub finalize {
    my ($self) = @_;

    return unless $self->placement_location->{ports}; # no data

    my $agt = $self->{strategy}{definition};
    my $entity_primary_field = $agt->{ports}{entity_primary_field} // 'hostname';

    for my $hostname (keys %{$self->placement_location->{ports}}) {
        my $ports = $self->placement_location->{ports}{$hostname};

        my $ports_provider = $self->schema->resultset($agt->{ports}{provider_class})
          ->single({ $entity_primary_field => $hostname });

        for my $allocation (@$ports) {
            $self->log->debugf("Inserting ports from %d, %d ports, for provider ID %d",
                               $allocation->{start}, $allocation->{num},
                               $ports_provider->provider_id);
            my $nr_port = $self->schema->resultset($agt->{ports}{nr_class})->create({
                provider_id => $ports_provider->provider_id,
                start_port  => $allocation->{start},
                num_ports   => $allocation->{num},
            });

            $self->log->debugf(
                "Creating an assignment of size %s (@%d) for provider ID %s, ag ID %s, cg ID %s",
                $allocation->{num}, $allocation->{start},
                $ports_provider->provider_id, $self->assignmentgroup->assignmentgroup_id,
                $self->commit_group_id,
            );

            my $assignment = $self->schema->resultset('Assignment')->create({
                provider_id        => $ports_provider->provider_id,
                assignmentgroup_id => $self->assignmentgroup->assignmentgroup_id,
                size               => $allocation->{num},
                committed          => $self->request->commit,
                commit_group_id    => $self->commit_group_id,
                resource_id        => $nr_port->resource_id,
            });
        }
    }

    return;
}

=head2 $self->postallocate()

A combined allocation and storage routine used by multi_place.
It works on the Result created by multi_place call to allocate ports on every
entity allocated by their resources.
Creates database entries for port allocation using Ports Result and
NR_* Result classes and creates the appropriate Assignment entries.
It's called as a Placementengine postallocate handler.

Populates every "placement_location" entry with a "ports" hashref.

=cut

sub postallocate {
    my($self, $result) = @_;

    my $agt = $self->{strategy}{definition};
    my $entity_primary_field = $agt->{ports}{entity_primary_field} // 'hostname';

    return unless $self->request->additional->{ports}; # no ports requested, nothing to do here

    my @container_names =
      map {$_->{placement_location}{$entity_primary_field}} @$result;

    my $container = $self->schema->resultset($agt->{ports}{container_class});

    $self->port_request(dclone($self->request->additional->{ports}));
    # set defaults
    $self->port_request->{min} //= 1024;
    $self->port_request->{max} //= 65535;
    $self->port_request->{sequential} //= 0;

    $self->port_request->{hosts} = [
        map { $self->schema->resultset($agt->{ports}{entity_class})
               ->single({ $entity_primary_field => $_ }) } @container_names
    ];
    $self->port_request->{host} = $self->port_request->{hosts}[0];

    my $lowest_port = $self->port_request->{min};
 CANDIDATE:
    while (1) {
        $self->port_response({ map { ## no critic (BuiltinFunctions::ProhibitVoidMap)
            $_ => {
                ports       => [],
                allocated   => 0,
            } } @container_names });

        while (my $current_host = $self->_select_host()) {
            my $min_range = $self->port_request->{sequential} ?
              $self->port_request->{ports} : 1;
            my $max_range = $self->port_request->{ports} - $self->port_response->{$current_host}{allocated};
            my $range = $self->_get_portrange($current_host, $min_range, $max_range, $lowest_port);

            unless ($range) { # start over allocation, port conflict
                $lowest_port = max($lowest_port, $self->port_request->{min}) + 1;

                if ($lowest_port > 2**16) {
                    Venn::Exception::Placement::PortsExhausted->throw({
                        hostname => $current_host
                    });
                }

                next CANDIDATE;
            }

            $self->_store_allocation($current_host, $range);
        }

        for my $hostname (keys $self->port_response) {
            for my $assignment (@$result) {
                if ($assignment->placement_location->{$entity_primary_field} eq $hostname) {
                    $assignment->placement_location->{ports} = $self->port_response->{$hostname}{ports};
                }
            }
        }

        last CANDIDATE;
    }

    for my $hostname (keys $self->port_response) {
        my $ports = $self->port_response->{$hostname}{ports};

        my $ports_provider = $self->schema->resultset($agt->{ports}{provider_class})
          ->single({ $entity_primary_field => $hostname });

        for my $allocation (@$ports) {
            $self->log->debugf("Inserting ports from %d, %d ports, for provider ID %d",
                               $allocation->{start}, $allocation->{num},
                               $ports_provider->provider_id);
            my $nr_port = $self->schema->resultset($agt->{ports}{nr_class})->create({
                provider_id => $ports_provider->provider_id,
                start_port  => $allocation->{start},
                num_ports   => $allocation->{num},
            });

            $self->log->debugf(
                "Creating an assignment of size %s (@%d) for provider ID %s, ag ID %s, cg ID %s",
                $allocation->{num}, $allocation->{start},
                $ports_provider->provider_id, $self->assignmentgroup->assignmentgroup_id,
                $self->commit_group_id,
            );

            my $assignment = $self->schema->resultset('Assignment')->create({
                provider_id        => $ports_provider->provider_id,
                assignmentgroup_id => $self->assignmentgroup->assignmentgroup_id,
                size               => $allocation->{num},
                committed          => $self->request->commit,
                commit_group_id    => $self->commit_group_id,
                resource_id        => $nr_port->resource_id,
            });
        }
    }

    return;
}

=head2 _get_portrange($hostname, $min_range, $max_range)

  param $hostname    - host to find a portrange for
  param $min_range   - minimum number of sequential number of ports to be found
                       1 if non-sequential allocation requested
  param $max_range   - maximum range to be found
  param $lowest_port - lower barrier override, used when conflict found -> reallocate higher

Called by placeports() and postallocate() for the current host to find next range candidate.

Returns undef when a port range could not be found.

=cut

sub _get_portrange {
    my ($self, $hostname, $min_range, $max_range, $lowest_port) = @_;

    my $alloc_map = $self->_get_alloc_map($hostname);

    my ($range_start, $range_counter);
    $self->port_response->{$hostname}{min_port} = max(($self->port_response->{$hostname}{min_port} // 0),
                                                      $self->port_request->{min} // 0,
                                                      $lowest_port // 0);
    my $current_port = $self->port_response->{$hostname}{min_port};
    my $response;

    while ($current_port <= $self->port_request->{max}+1) {
        if (! $range_start) {
            if (my @allocation = @{$alloc_map->find($current_port, $current_port)}) { # assigned
                $current_port += $allocation[0]{num}; # skip ports
                next;
            }
            else { # not assigned
                $range_start = $current_port; # save the port
                $range_counter = 1;
                if ($range_counter == $min_range && !$alloc_map->find($current_port, $current_port)) {
                    # single-port range found and not allocated
                    $response = {
                        start => $range_start,
                        num   => $range_counter,
                    };
                    last;
                }
            }
        }
        else { # in range
            if (my @allocation = @{$alloc_map->find($current_port, $current_port)}) { # assigned
                if ($range_counter >= $min_range) {
                    # right range found
                    $response = {
                        start => $range_start,
                        num   => $range_counter,
                    };
                    last;
                }

                $current_port += $allocation[0]{num}; # skip ports
                $range_start = undef;
                next;
            }
            else {
                if ($range_counter >= $min_range && $range_counter == $max_range) {
                    # right range found
                    $response = {
                        start => $range_start,
                        num   => $range_counter,
                    };
                    last;
                }

                ++$range_counter;
            }
        }
        ++$current_port;
    }

    $self->port_response->{$hostname}{min_port} = $current_port; # save for next iteration

    return $response;
}


=head2 $self->_get_alloc_map($value)

  param $value - (String) identifier to fetch allocation map for scope
                 hostname for 'hostgroup'
                 building_code for 'building'
                 continent_code for 'continent'
                 ignored for 'global'

Caches the allocation map for a scope. Selects all allocated ports from
NR_Farm_Port Result class. Uses $self->{_alloc_map} as cache storage.
The scope is determined by the $self->port_request->{samerange} parameter,
which defaults to 'hostgroup'.

Returns an IntervalTree object with all ranges inserted as closed intervals.

eg.:
    my $tree = IntervalTree->new;
    $tree->insert($start_port1, $end_port1, {
       start => $start_port1, end => $end_port1, num => $num_ports1,
    });
    ...

=cut

sub _get_alloc_map {
    my ($self, $value) = @_;
    my $scope = $self->port_request->{samerange} // 'entity'; # limit SELECT to scope, default just the host

    my $agt = $self->{strategy}{definition};

    $self->{_alloc_map} //= {};
    my $entity = $agt->{ports}{entity};
    my $entity_primary_field = $agt->{ports}{entity_primary_field} // 'hostname';
    my $link_column = $agt->{ports}{entity_to_container_function};
    my $container_name = $self->port_request->{host}->$link_column;
    my $building = $self->port_request->{host}->building;
    my $continent = $self->port_request->{host}->continent;

    my ($key, %where, %exclusion_where);
    given ($scope) {
        when (/^entity$/) {
            %where = ( "$agt->{ports}{entity}.$entity_primary_field" => $value );
            $key = $value;
            %exclusion_where = ('-or' => [{global => 1}, {continent => $continent},
                                          {building => $building},
                                          {$link_column => $container_name},
                                          {$entity_primary_field => $value}]);
        }
        when (/^container$/) {
            %where = ( "$entity.$link_column" => $container_name );
            $key = "container_$container_name";
            %exclusion_where = ('-or' => [{global => 1}, {continent => $continent},
                                          {building => $building},
                                          {$link_column => $container_name}]);
        }
        when (/^building$/)  {
            %where = ( 'building' => $building );
            $key = "building_$building";
            %exclusion_where = ('-or' => [{global => 1}, {continent => $continent},
                                          {building => $building}]);
        }
        when (/^continent$/)  {
            %where = ( 'continent' => $continent );
            $key = "continent_$continent";
            %exclusion_where = ('-or' => [{global => 1}, {continent => $continent}]);
        }
        when (/^global$/) {
            %where = ();
            $key = 'global';
            %exclusion_where = (global => 1);
        }
        default { die "_get_alloc_map: unsupported scope $scope" }
    }

    unless ($self->{_alloc_map}{$key}) {
        my $tree = IntervalTree->new();

        my @allocated_ports = $self->schema->resultset($agt->{ports}{nr_class})
        ->search(\%where, {
            select => [qw/ start_port num_ports /],
            join => { provider => { $agt->{ports}{provider_relation} => $entity } },
        })
        ->as_hash
        ->all;

        for my $row (@allocated_ports) {
            # +1,-1 because tree uses open intervals, we need closed
            $tree->insert($row->{start_port}-1, $row->{start_port}+$row->{num_ports}, {
                start => $row->{start_port},
                end   => $row->{start_port}+$row->{num_ports},
                num   => $row->{num_ports},
            });
        }

        my @excluded_ports = $self->schema->resultset($agt->{ports}{exclusion_class})
        ->search(\%exclusion_where, {
            select => [qw/ start_port num_ports /],
        })
        ->as_hash
        ->all;

        for my $row (@excluded_ports) {
            $tree->insert($row->{start_port}-1, $row->{start_port}+$row->{num_ports}, {
                start => $row->{start_port},
                end   => $row->{start_port}+$row->{num_ports},
                num   => $row->{num_ports},
            });
        }

        $self->{_alloc_map}{$key} = $tree;
    }

    return $self->{_alloc_map}{$key};
}

=head2 $self->_store_allocation($hostname, $range)

  param $hostname - hostname to store
  param $range - hashref of allocation returned by _get_portrange

If 'sameports' not set, it stores the range for $hostname in
$self->port_response.
When 'sameports' specified it checks for port allocation conflict in the
specified scope ('hostgroup', 'building', 'continent' or 'global').
Gets the allocation map for the specified scope and checks every member
for the allocation range.
When a conflict found, it returns without storing the allocation range.
Otherwise stores range for all hosts in $self->port_response.

=cut

sub _store_allocation {
    my ($self, $hostname, $range) = @_;

    my @store_for = ($hostname);

    if ($self->port_request->{samerange}) {
        for my $current (keys %{$self->port_response}) { # check port allocation on each host
            next if $hostname eq $current; # don't check self

            my $alloc_map = $self->_get_alloc_map($current);

            return if @{$alloc_map->find($range->{start},
                                         $range->{start}+$range->{num}-1)};

            # store it for all hosts
            @store_for = keys %{$self->port_response};
        }
    }

    # store it
    for my $host (@store_for) {
        push @{$self->port_response->{$host}{ports}}, $range;
        $self->port_response->{$host}{allocated} += $range->{num};
    }

    return;
}

1;
