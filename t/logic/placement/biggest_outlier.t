#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 14;
use Catalyst::Test 'Venn';
use Data::Dumper;
use HTTP::Request::Common qw( GET PUT POST DELETE );
use JSON::XS;
use Storable 'dclone';

use Venn::PlacementEngine;

my $schema = testschema();

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1, } );

    bootstrap();

    # ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner)
    create_racks('ny', 'zy', 5, 2, 2, 2, [ 'dev' ], [ 1 ]);

    #create some other racks that shouldn't matter, because of env, owner, building, or region
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'qa' ], [ 1 ]);
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 2 ]);
    create_racks('ln', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);
    create_racks('ny', 'zz', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);
}

$schema->resultset('AssignmentGroup')->delete_all();
$schema->resultset('Assignment')->delete_all();

# zyecl1 [7,8], nyn1 [1], vmdisk1 [2]

# my ($vm, $provider_id, $size, $committed) = @_;
assign('evmzy1', 7, 8, 1); #memory
assign('evmzy1', 8, 2000, 1); #cpu
assign('evmzy1', 1, 20, 1); #io
assign('evmzy1', 2, 60, 1); #disk

assign('evmzy2', 7, 4, 1); #mem
assign('evmzy2', 8, 1000, 1); #cpu
assign('evmzy2', 1, 10, 1); #io
assign('evmzy2', 2, 30, 1); #disk

assign('evmzy7', 9, 16, 1); #mem
assign('evmzy7', 10, 3000, 1); #cpu
assign('evmzy7', 11, 20, 1); #io
assign('evmzy7', 12, 60, 1); #disk

assign('evmzy8', 9, 4, 1); #mem
assign('evmzy8', 10, 4000, 1); #cpu
assign('evmzy8', 11, 30, 1); #io
assign('evmzy8', 12, 100, 1); #disk


#totals:
#  memory:
#    7 (zyecl1) has total 12, avg 6
#    9 (zyecl2) has total 20, avg 10 ( has to pick this because of cpu )
#  cpu:
#    8 ( zyecl1 ) has total 3000, avg 1500
#    10 (zyecl2 ) has total 7000, avg 3500 ( pick this first)
#  io:
#    1 ( nyn1 ) has total 30, avg 15
#    11 ( nyn3 ) has total 50, avg 25 (pick this)
#  disk:
#    2 ( vmdisk1 on nyn1 ) has total 90, avg 45
#    12 ( vmdisk 5 on nyn3 ) has total 160, avg 80 (pick this)

my $placement = {
    resources => {
        ram => 16, # avg should be 8, so should be above avg. pick this one second (desc).
        cpu => 1000, #avg should be 2500, should be way below. pick this one first (ascending).
        filerio => 20, #avg should be 20. this should be last in the sort order (asc).
        disk => 62, #avg should be 62.5. should be 3rd (asc)
    },
    attributes => {
        environment => 'dev',
        capability => {
            #ram => [qw /ibm hp/],
        },
        owner => [1],
    },
    location => {
        campus => 'ny',
        building => 'zy',
    },
    friendly => 'evmx123',
};

    #on resources that should be ignored
    #zy6
    assign('evmzy6', 57, 2, 1);
    assign('evmzy6', 58, 1010, 1);
    assign('evmzy6', 51, 11, 1);
    assign('evmzy6', 52, 39, 1);
    # #zy7
    assign('evmzy5', 67, 5, 1);
    assign('evmzy5', 68, 1007, 1);
    assign('evmzy5', 61, 12, 1);
    assign('evmzy5', 62, 31, 1);
    # #zy8
    assign('evmzy4', 77, 5, 1);
    assign('evmzy4', 80, 1005, 1);
    assign('evmzy4', 71, 13, 1);
    assign('evmzy4', 73, 22, 1);
    # #zz9
    assign('evmzy3', 89, 24, 1);
    assign('evmzy3', 88, 5000, 1);
    assign('evmzy3', 84, 30, 1);
    assign('evmzy3', 85, 90, 1);

$schema->lower_optimization_class(1);

eval {
        remove_environment_from_provider(7, 'newenv');
        remove_environment_from_provider(8, 'newenv');
        remove_environment_from_provider(1, 'newenv');
        remove_environment_from_provider(2, 'newenv');
    };

eval { remove_capability_from_provider(10, 'supercharged') }; #clean up from previous runs in no_deploy
eval { remove_capability_from_provider(10, 'explicit_feature') }; #clean up from previous runs in no_deploy
eval { remove_capability_from_provider(10, 'nonexplicit_feature') }; #clean up from previous runs in no_deploy

eval {
    remove_owner_from_provider(7, '111');
    remove_owner_from_provider(8, '111');
    remove_owner_from_provider(1, '111');
    remove_owner_from_provider(2, '111');
};

my $placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

ok my $placement_result = ($placement_engine->place)[0], 'biggest outlier placement runs.';

my $placed_avg_qty = {
    'disk' => '62.5',
    'cpu' => '2500',
    'ram' => '8',
    'filerio' => '20'
};

is_deeply $placement_result->placement_info->{assigned_avg_quantity}, $placed_avg_qty,  'assigned avg quantity working.';

my $percent_diff = {
    'disk' => '0.00803212851405622',
    'cpu' => '0.857142857142857',
    'ram' => '0.666666666666667',
    'filerio' => '0'
};

is_deeply $percent_diff, $placement_result->placement_info->{sorting}->{abs_percentages}, 'percent difference is correct';
my $sort_order = [
    { '-asc' => 'cpu_unassigned' },
    { '-desc' => 'ram_unassigned' },
    { '-asc' => 'disk_unassigned' },
    { '-asc' => 'filerio_unassigned' },
];
is_deeply $sort_order,  $placement_result->placement_info->{sorting}->{sql_order}, 'sort order is correct';

my @results = ($placement_result->placement_rs->as_hash_round->all)[0..10];

my $results_string = do { local $/ = undef; <DATA> };

my $correct_results =  eval($results_string); ## no critic (ProhibitStringyEval)

is_deeply \@results, $correct_results, 'validated all results';

my $placement2 = dclone $placement;

eval { create_capability('supercharged', '', 0) };

$placement2->{attributes}->{capability}->{cpu} = [ 'supercharged' ];

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement2, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

my $placed = ($placement_engine->place)[0]->placement_rs;

is $placed->first, undef, 'no ram resources with capability of supercharged';


add_capability_to_provider(10, 'supercharged');

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement2, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

my $row = $placed->as_hash->first;
is $row->{cpu_provider_id}, 10, 'picks the provider with the capability.';


my $placement3 = dclone $placement ;
$placement3->{attributes}->{environment} = 'newenv';

eval { create_environment('newenv', 'test env') };

    eval {
        remove_environment_from_provider(7, 'newenv');
        remove_environment_from_provider(8, 'newenv');
        remove_environment_from_provider(1, 'newenv');
        remove_environment_from_provider(2, 'newenv');
    };
    if ($@) { warn $@ };

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement3, {
     schema  => $schema,
     all_rows => 1,
    simulate => 1,
});


$placed = ($placement_engine->place)[0]->placement_rs;

is $placed->first, undef, 'no resources in newenv';

add_environment_to_provider(7, 'newenv');
add_environment_to_provider(8, 'newenv');
add_environment_to_provider(1, 'newenv');
add_environment_to_provider(2, 'newenv');

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement3, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

$row = $placed->as_hash_round->first;

my $env_result = {
        'disk_share_name' => 'vmdisk1',
        'filerio_filer_name' => 'nyn1',
        'ram_provider_id' => '7.00',
        'disk_unassigned' => '13573927.00',
        'cpu_unassigned' => '349000.00',
        'disk_provider_id' => '2.00',
        'cluster_name' => 'zyecl1',
        'cpu_cluster_name' => 'zyecl1',
        'filerio_unassigned' => '16970.00',
        'ram_unassigned' => '5242868.00',
        'cpu_provider_id' => '8.00',
        'filerio_provider_id' => '1.00'
    };

is_deeply  $row, $env_result, 'pulls the providers with the correct environment';

###

my $placement4 = dclone $placement;

eval {   create_owner('111') };

$placement4->{attributes}->{owner} = [ qw/ 111 456 / ];

eval {
    remove_owner_from_provider(7, '111');
    remove_owner_from_provider(8, '111');
    remove_owner_from_provider(1, '111');
    remove_owner_from_provider(2, '111');
};

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement4, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

is $placed->first, undef, 'no resources with correct owners';


add_owner_to_provider(7, '111');
add_owner_to_provider(8, '111');
add_owner_to_provider(1, '111');
add_owner_to_provider(2, '111');

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement4, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

$row = $placed->as_hash_round->first;
is_deeply $row, $env_result, 'picks the providers with the correct owners.';



my $placement5 = dclone $placement;

eval {
    create_capability('explicit_feature', '', 1);
    create_capability('nonexplicit_feature', '', 0);
};

$placement5->{attributes}->{capability}->{cpu} = [ 'supercharged' ];

eval { remove_capability_from_provider(10, 'supercharged') };
eval { remove_capability_from_provider(10, 'explicit_feature') };
eval { remove_capability_from_provider(10, 'nonexplicit_feature') };

add_capability_to_provider(10, 'nonexplicit_feature');
add_capability_to_provider(10, 'supercharged');

$schema->resultset('AssignmentGroup')->delete_all();
$schema->resultset('Assignment')->delete_all();

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement5, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

$row = $placed->as_hash->first;

is $row->{cpu_provider_id}, 10, 'picks the provider with the supercharged capability. nonexplicit feature does not block.';

add_capability_to_provider(10, 'explicit_feature');

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement5, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

is $placed->first, undef, 'non-specified explicit capability blocks the placement';

$placement5->{attributes}->{capability}->{cpu} = [ 'explicit_feature', 'supercharged' ];

$placement_engine = Venn::PlacementEngine->create('biggest_outlier', 'hosting', $placement5, {
    schema  => $schema,
    all_rows => 1,
    simulate => 1,
});

$placed = ($placement_engine->place)[0]->placement_rs;

$row = $placed->as_hash->first;
is $row->{cpu_provider_id}, 10, 'with the explicit feature in the request, it works again.';

###
$schema->raise_optimization_class();
done_testing();
1;


__DATA__
[
    {
        'disk_share_name' => 'vmdisk1',
        'filerio_filer_name' => 'nyn1',
        'ram_provider_id' => '9.00',
        'disk_unassigned' => '13573927.00',
        'cpu_unassigned' => '345000.00',
        'disk_provider_id' => '2.00',
        'cluster_name' => 'zyecl2',
        'cpu_cluster_name' => 'zyecl2',
        'filerio_unassigned' => '16970.00',
        'ram_unassigned' => '5242860.00',
        'cpu_provider_id' => '10.00',
        'filerio_provider_id' => '1.00'
    },
    {
        'disk_share_name' => 'vmdisk2',
        'filerio_filer_name' => 'nyn1',
        'ram_provider_id' => '9.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '345000.00',
        'disk_provider_id' => '3.00',
        'cluster_name' => 'zyecl2',
        'cpu_cluster_name' => 'zyecl2',
        'filerio_unassigned' => '16970.00',
        'ram_unassigned' => '5242860.00',
        'cpu_provider_id' => '10.00',
        'filerio_provider_id' => '1.00'
    },
    {
        'disk_share_name' => 'vmdisk3',
        'filerio_filer_name' => 'nyn2',
        'ram_provider_id' => '9.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '345000.00',
        'disk_provider_id' => '5.00',
        'cluster_name' => 'zyecl2',
        'cpu_cluster_name' => 'zyecl2',
        'filerio_unassigned' => '17000.00',
        'ram_unassigned' => '5242860.00',
        'cpu_provider_id' => '10.00',
        'filerio_provider_id' => '4.00'
    },
    {
        'disk_share_name' => 'vmdisk4',
        'filerio_filer_name' => 'nyn2',
        'ram_provider_id' => '9.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '345000.00',
        'disk_provider_id' => '6.00',
        'cluster_name' => 'zyecl2',
        'cpu_cluster_name' => 'zyecl2',
        'filerio_unassigned' => '17000.00',
        'ram_unassigned' => '5242860.00',
        'cpu_provider_id' => '10.00',
        'filerio_provider_id' => '4.00'
    },
    {
        'disk_share_name' => 'vmdisk1',
        'filerio_filer_name' => 'nyn1',
        'ram_provider_id' => '7.00',
        'disk_unassigned' => '13573927.00',
        'cpu_unassigned' => '349000.00',
        'disk_provider_id' => '2.00',
        'cluster_name' => 'zyecl1',
        'cpu_cluster_name' => 'zyecl1',
        'filerio_unassigned' => '16970.00',
        'ram_unassigned' => '5242868.00',
        'cpu_provider_id' => '8.00',
        'filerio_provider_id' => '1.00'
    },
    {
        'disk_share_name' => 'vmdisk2',
        'filerio_filer_name' => 'nyn1',
        'ram_provider_id' => '7.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '349000.00',
        'disk_provider_id' => '3.00',
        'cluster_name' => 'zyecl1',
        'cpu_cluster_name' => 'zyecl1',
        'filerio_unassigned' => '16970.00',
        'ram_unassigned' => '5242868.00',
        'cpu_provider_id' => '8.00',
        'filerio_provider_id' => '1.00'
    },
    {
        'disk_share_name' => 'vmdisk3',
        'filerio_filer_name' => 'nyn2',
        'ram_provider_id' => '7.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '349000.00',
        'disk_provider_id' => '5.00',
        'cluster_name' => 'zyecl1',
        'cpu_cluster_name' => 'zyecl1',
        'filerio_unassigned' => '17000.00',
        'ram_unassigned' => '5242868.00',
        'cpu_provider_id' => '8.00',
        'filerio_provider_id' => '4.00'
    },
    {
        'disk_share_name' => 'vmdisk4',
        'filerio_filer_name' => 'nyn2',
        'ram_provider_id' => '7.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '349000.00',
        'disk_provider_id' => '6.00',
        'cluster_name' => 'zyecl1',
        'cpu_cluster_name' => 'zyecl1',
        'filerio_unassigned' => '17000.00',
        'ram_unassigned' => '5242868.00',
        'cpu_provider_id' => '8.00',
        'filerio_provider_id' => '4.00'
    },
    {
        'disk_share_name' => 'vmdisk5',
        'filerio_filer_name' => 'nyn3',
        'ram_provider_id' => '17.00',
        'disk_unassigned' => '13573857.00',
        'cpu_unassigned' => '352000.00',
        'disk_provider_id' => '12.00',
        'cluster_name' => 'zyecl3',
        'cpu_cluster_name' => 'zyecl3',
        'filerio_unassigned' => '16950.00',
        'ram_unassigned' => '5242880.00',
        'cpu_provider_id' => '18.00',
        'filerio_provider_id' => '11.00'
    },
    {
        'disk_share_name' => 'vmdisk5',
        'filerio_filer_name' => 'nyn3',
        'ram_provider_id' => '19.00',
        'disk_unassigned' => '13573857.00',
        'cpu_unassigned' => '352000.00',
        'disk_provider_id' => '12.00',
        'cluster_name' => 'zyecl4',
        'cpu_cluster_name' => 'zyecl4',
        'filerio_unassigned' => '16950.00',
        'ram_unassigned' => '5242880.00',
        'cpu_provider_id' => '20.00',
        'filerio_provider_id' => '11.00'
    },
    {
        'disk_share_name' => 'vmdisk6',
        'filerio_filer_name' => 'nyn3',
        'ram_provider_id' => '17.00',
        'disk_unassigned' => '13574017.00',
        'cpu_unassigned' => '352000.00',
        'disk_provider_id' => '13.00',
        'cluster_name' => 'zyecl3',
        'cpu_cluster_name' => 'zyecl3',
        'filerio_unassigned' => '16950.00',
        'ram_unassigned' => '5242880.00',
        'cpu_provider_id' => '18.00',
        'filerio_provider_id' => '11.00'
    },
];
