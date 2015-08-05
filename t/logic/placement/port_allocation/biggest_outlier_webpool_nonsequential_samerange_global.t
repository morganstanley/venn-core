#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 2;

use Venn::PlacementEngine;

my $schema = testschema();

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1 } );

    bootstrap();

    # ($building, $num_hg, $hosts_per_hg, $envs, $owner)
    create_webpools('na', 'xy', 5, 2, [ 'dev' ], [ 1 ]);

    #create some other WPs that shouldn't matter, because of env, owner, building
    create_webpools('na', 'zy', 1, 2, [ 'qa' ], [ 1 ]);
    create_webpools('eu', 'zq', 2, 2, [ 'prod' ], [ 1 ]);

    # my ($vm, $provider_id, $size, $committed) = @_;
    assign('host1', 1, 256, 1, 'webpool'); # ram
    assign('host1', 2, 500, 1, 'webpool'); # cpu

    assign_hostport('portrange1', 3, 1025, 48); # hostports
    assign_hostport('portrange2', 6, 1075, 10); # hostports in same WP
    assign_hostport('portrange3', 9, 1026, 1); # hostports in same WP
    assign_hostport('portrange4', 12, 1086, 10); # hostports in another WP, same building
    assign_hostport('portrange5', 15, 1099, 10); # hostports in another WP, same building
    assign_hostport('portrange6', 39, 1111, 10); # hostports in another building, same continent
    assign_hostport('portrange7', 99, 1096, 100); # hostports in another continent

    assign('host2', 4, 64, 1, 'webpool'); # ram
    assign('host2', 5, 100, 1, 'webpool'); # cpu
}

my $placement = {
    friendly => 'test',
    resources => {
        hostram => 128,
        hostcpu => 300,
    },
    additional => {
        ports => {
            ports => 5, # number of ports
            min => 1024, # minimum allocation range
            max => 10400, # max allocation range
            sequential => 0, # allocate non-sequentially
            samerange => 'global', # allocate same ranges for all hosts
                                   # globally
        },
    },
    attributes => {
        environment => 'dev',
        owner => [1],
    },
    location => {
        continent => 'na',
        building => 'xy',
    },
    instances => 3,
};

my $result_string = do { local $/ = undef; <DATA> };
my $correct_result =  eval($result_string); ## no critic (ProhibitStringyEval)

$schema->lower_optimization_class();

my $placement_engine = Venn::PlacementEngine->create(
    'biggest_outlier', 'webpool',
    $placement,
    { schema  => $schema, all_rows => 1 },
);

ok my @placement_result = $placement_engine->place, 'biggest outlier placement runs.';

my $locations = [map {$_->placement_location} @placement_result];
is_deeply $locations, $correct_result, 'placement_location valid';


$schema->raise_optimization_class();

done_testing();

1;

__DATA__
[
    {
        'ports' => [
            {
                'num' => 1,
                'start' => 1024
            },
            {
                'num' => 2,
                'start' => 1073
            },
            {
                'num' => 1,
                'start' => 1085
            },
            {
                'num' => 1,
                'start' => 1196
            }
        ],
        'hostram_provider_id' => 1,
        'hostcpu_unassigned' => '2500',
        'hostname' => 'naxy1_host1',
        'hostram_unassigned' => '16128',
        'hostcpu_hostname' => 'naxy1_host1',
        'hostcpu_provider_id' => 2
    },
    {
        'ports' => [
            {
                'num' => 1,
                'start' => 1024
            },
            {
                'num' => 2,
                'start' => 1073
            },
            {
                'num' => 1,
                'start' => 1085
            },
            {
                'num' => 1,
                'start' => 1196
            }
        ],
        'hostram_provider_id' => 7,
        'hostcpu_unassigned' => '3000',
        'hostname' => 'naxy1_host3',
        'hostram_unassigned' => '16384',
        'hostcpu_hostname' => 'naxy1_host3',
        'hostcpu_provider_id' => 8
    },
    {
        'ports' => [
            {
                'num' => 1,
                'start' => 1024
            },
            {
                'num' => 2,
                'start' => 1073
            },
            {
                'num' => 1,
                'start' => 1085
            },
            {
                'num' => 1,
                'start' => 1196
            }
        ],
        'hostram_provider_id' => 10,
        'hostcpu_unassigned' => '3000',
        'hostname' => 'naxy2_host4',
        'hostram_unassigned' => '16384',
        'hostcpu_hostname' => 'naxy2_host4',
        'hostcpu_provider_id' => 11
    }
]
