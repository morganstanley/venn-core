#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 7;
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
    create_racks('eu', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);
    create_racks('ny', 'zz', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);

    # my ($vm, $provider_id, $size, $committed) = @_;
    assign('evmzy1', 7, 8, 1);
    assign('evmzy1', 8, 2000, 1);
    assign('evmzy1', 1, 20, 1);
    assign('evmzy1', 2, 60, 1);

    assign('evmzy2', 7, 4, 1);
    assign('evmzy2', 8, 1000, 1);
    assign('evmzy2', 1, 10, 1);
    assign('evmzy2', 2, 30, 1);

    #on resources that should be ignored
    #zy6
    assign('evmzy6', 57, 2, 1);
    assign('evmzy6', 58, 1010, 1);
    assign('evmzy6', 51, 11, 1);
    assign('evmzy6', 52, 39, 1);
    #zy7
    assign('evmzy5', 67, 5, 1);
    assign('evmzy5', 68, 1007, 1);
    assign('evmzy5', 61, 12, 1);
    assign('evmzy5', 62, 31, 1);
    #zy8
    assign('evmzy4', 77, 5, 1);
    assign('evmzy4', 80, 1005, 1);
    assign('evmzy4', 71, 13, 1);
    assign('evmzy4', 73, 22, 1);
    #zz9
    assign('evmzy3', 89, 24, 1);
    assign('evmzy3', 88, 5000, 1);
    assign('evmzy3', 84, 30, 1);
    assign('evmzy3', 85, 90, 1);
}

my %placement = (
    resources => {
        ram => 4,
        cpu => 2000,
        filerio => 20,
        disk => 60,
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
        continent => 'na',
        building => 'zy',
    },
    friendly => 'evmx123',
);

my $placement_engine = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});

$schema->lower_optimization_class();

my $r = $placement_engine->join_correlate_filter({ test_columns => 1})->as_hash->first;

is $r->{filerio_filer_name}, 'nyn1', 'correct filerio filer name for auto placement';
is $r->{cluster_name}, 'zyecl1', 'correct ram cluster name for auto placement';
is $r->{cpu_cluster_name}, 'zyecl1', 'correct cpu cluster for auto placement';
is $r->{disk_share_name}, 'vmdisk1', 'correct disk share for auto placement';

#add manual placement to placement request
$placement{'manual_placement'}->{disk} = 'vmdisk2';
my $placement_engine2 = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});
$r = $placement_engine2->join_correlate_filter()->as_hash->first;
is $r->{disk_share_name}, 'vmdisk2', 'disk share manually set to vmdisk2';

#this isn't gonna fit!
$placement{resources}->{ram} = 1000000000;
$placement{manual_placement}->{ram} = 'zyecl2';
my $placement_engine3 = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});
$r = $placement_engine3->join_correlate_filter()->as_hash->first;
is $r->{cluster_name}, undef, 'can not assign this huge request.';

#force_placement bypasses the capacity check
$placement{force_placement} = 1;
my $placement_engine4 = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});
$r = $placement_engine4->join_correlate_filter()->as_hash->first;
is $r->{cluster_name}, 'zyecl2', 'force_placement to zyecl2 works.';

$schema->raise_optimization_class();
