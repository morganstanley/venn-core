package Venn::PlacementEngine;

=head1 NAME

Venn::PlacementEngine

=head1 DESCRIPTION

Places resources given a strategy, assignment group type, resources, attributes, etc.

=head1 SYNOPSIS

    my $placement = {
        resources => {
            memory => 16,
            cpu => 1000,
            io => 20,
            disk => 62,
        },
        attributes => {
            environment => 'dev',
            capability => {
                memory => [qw/ ibm hp /],
                cpu    => [qw/ ibm hp /]
            },
            owner => [1],
        },
        location => {
            continent => 'na'
        },
        friendly => 'vm123',
        instances => 1,
    };

    my $placement_engine = Venn::PlacementEngine->create('stragegy_name', 'agt_name', $placement);

    my @placement_results = $placement_engine->place();

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
use MooseX::ClassAttribute;
use Moose::Util qw( does_role );
with 'Venn::Role::Logging';
use namespace::clean -except => [qw( meta _strategy_packages )];

use Venn::Exception qw(
    API::InvalidPlacementStrategy
);

use Module::Pluggable
    sub_name    => '_strategy_packages',
    search_path => 'Venn::PlacementEngine::Strategy',
    require     => 1,
    inner       => 1,
;

class_has 'strategies' => (
    is      => 'ro',
    isa     => 'HashRef[Venn::PlacementEngine::Strategy]',
    builder => '_build_strategies',
    documentation => 'Hash reference of strategies via their names',
);

has '_init_args' => (
    is       => 'rw',
    isa      => 'HashRef',
    documentation => 'Internal init_args for creating strategy objects',
);

has '_strategy_name' => (
    is       => 'rw',
    isa      => 'Str',
    documentation => 'Internal strategy name for creating strategy objects',
);

has 'strategy' => (
    is       => 'ro',
    isa      => 'Venn::PlacementEngine::Strategy',
    lazy     => 1,
    builder  => '_build_strategy',
    documentation => 'Accessor to current Strategy object',
);

=head1 METHODS

=head2 create($strategy, $assignmentgroup_type, $request_hash, $init_args)

Creates a new Placement Engine instance.

Expects a request hash that looks like this:

    my %placement = (
        // list of all resources and amount requested
        resources => {
            memory => 16,
            cpu    => 1000,
            io     => 20,
            disk   => 62,
        },
        // placement providers require these attributes
        attributes => {
            // environment for all providers
            environment  => 'dev',
            // with these capabilities
            capabilities => {
                // disk must be tagged with ssd
                disk => [qw/ ssd /],
            },
        },
        // location hints (stored in assignment group type metadata)
        location => {
            campus   => 'ny',
        }
        instances => 1,
    );


    param  $strategy             : (Str) Strategy name
    param  $assignmentgroup_type : (Str) Name of an Assignment Group Type
    param \%request_hash         : (HashRef) hash containing placement request (resources, attrs, location, etc.)
    param \%init_args            : (HashRef) Args to be passed to the Strategy's constructor (manual schema, etc.)

    return                       : (isa Venn::PlacementEngine) PlacementEngine instance object

=cut

sub create {
    my ($self, $strategy, $assignmentgroup_type, $request_hash, $init_args) = @_;

    if (! exists $self->strategies->{$strategy}) {
        Venn::Exception::API::InvalidPlacementStrategy->throw({ strategy => $strategy });
    }

    # The request will parse the raw json from the client
    $init_args->{request} = Venn::PlacementEngine::Request->new(
        assignmentgroup_type => $assignmentgroup_type,
        raw_request          => $request_hash,
    );

    my $instance = $self->new(
        _strategy_name => $strategy,
        _init_args     => $init_args,
    );

    return $instance;
}

=head2 place()

Runs placement based on a placement request, returns placement results.

    return : Array(Venn::PlacementEngine::Result) placement results

=cut

sub place {
    my ($self) = @_;

    die "Placement engine has not been initialized!" unless $self->_init_args;

    my ($placement, @instances, @placement_result);
    my $request = $self->_init_args->{request};

    while (@instances < $request->instances) {
        if ($placement) {
            # exclude allocated instances
            $request->location->{hostname} = {'-and' => []}; # FIXME! dynamic field?
            for (@instances) {
                push $request->location->{hostname}{'-and'}, { 'hostname' => {'!=' => $_} };
            }
        }

        my $strategy = $self->strategies->{$self->_strategy_name}->new($self->_init_args);
        $strategy->validate_request_resources($self->_init_args->{request});
        $placement = $strategy->place();

        push @placement_result, $placement;

        given ($placement->state) {
            when (/^Placed$/) {
                push @instances, $placement->placement_location->{hostname}; # FIXME! dynamic field?
                # they should end up in the same assignment group, commit group
                $self->_init_args->{assignment_group} ||= $placement->assignmentgroup->identifier if $placement->assignmentgroup;
                $self->_init_args->{commit_group_id} ||= $placement->commit_group_id if $placement->commit_group_id;
            }
            when (/^(?:NotPlaced|NoCapacity)$/) {
                last;
            }
            default {
                die "Unknown Placement state encountered: ".$placement->state;
            }
        }
    }

    if (@placement_result && $placement_result[-1]->state =~ /^Placed$/) {
        $placement_result[-1]->_run_resultprocessing(\@placement_result);
    }

    return @placement_result;
}

=head2 _build_strategy()

Initializes the current strategy for lazy-defined $self->strategy accessor.

=cut

sub _build_strategy {
    my ($self) = @_;

    die "Placement engine has not been initialized!" unless $self->_init_args;

    my $strategy = $self->strategies->{$self->_strategy_name}->new($self->_init_args);
    $strategy->validate_request_resources($self->_init_args->{request});

    return $strategy;
}

=head2 capacity($request)

Proxy method to the current Strategy->capacity($request)

=head2 join_correlate_filter()

Proxy method to the current Strategy->join_correlate_filter()

=head2 avg_resources

Proxy method to the current Strategy->avg_resources()

=cut

## no critic Subroutines::RequireArgUnpacking

sub capacity              { return shift->strategy->capacity(@_) }
sub join_correlate_filter { return shift->strategy->join_correlate_filter(@_) }
sub avg_resources         { return shift->strategy->avg_resources(@_) }

## use critic

=head2 _build_strategies()

Builds a list of all available strategies using Module::Pluggable.
It's a class-scoped loader.

    return : (HashRef) Mapping of strategy name => strategy class

=cut

sub _build_strategies {
    my %strategies;

    for my $strategy (__PACKAGE__->_strategy_packages) {
        # Only allow strats that use the interface
        next unless does_role($strategy, 'Venn::PlacementEngine::StrategyInterface');

        # Disallow duplicates
        die sprintf(
            "Strategy: %s in '%s' already defined in '%s'",
            $strategy->name, $strategy, $strategies{$strategy->name},
        ) if defined $strategies{$strategy->name};

        $strategies{$strategy->name} = $strategy;
    }

    return \%strategies;
}

__PACKAGE__->meta->make_immutable;
