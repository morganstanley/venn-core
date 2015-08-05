#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 4;
use Venn::PlacementEngine;

my $schema = testschema();

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1, } );

    bootstrap();

    # ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner)
    create_racks('ny', 'zy', 5, 2, 2, 2, [ 'dev' ], [ 1,2 ]);

    #create some other racks that shouldn't matter, because of env, owner, building, or region
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'qa' ], [ 1,2 ]);
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'dev','qa' ], [ 3,4 ]);
    create_racks('ln', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 1,2 ]);
    create_racks('ny', 'zz', 1, 2, 2, 2, [ 'dev' ], [ 1,2 ]);

    #my ($vm, $provider_id, $size, $committed) = @_;
    assign('evmzy1', 7, 8, 1);
    assign('evmzy1', 8, 2000, 1);
    assign('evmzy1', 1, 20, 1);
    assign('evmzy1', 2, 60, 1);

    assign('evmzy2', 7, 4, 1);
    assign('evmzy2', 8, 1000, 1);
    assign('evmzy2', 1, 10, 1);
    assign('evmzy2', 2, 30, 1);

    assign('evmzy7', 9, 16, 1);
    assign('evmzy7', 18, 3000, 1);
    assign('evmzy7', 11, 20, 1);
    assign('evmzy7', 12, 60, 1);

    assign('evmzy8', 9, 4, 1);
    assign('evmzy8', 18, 4000, 1);
    assign('evmzy8', 11, 30, 1);
    assign('evmzy8', 12, 100, 1);

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
}

my %placement = (
    resources => {
        ram => 0, #4,
        cpu => 0, #2000,
        filerio => 0, #20,
        disk => 0, #60,
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
);

my $placement_engine = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});

$schema->lower_optimization_class();

my $jcf = $placement_engine->join_correlate_filter();

my $r = $placement_engine->avg_resources();

cmp_ok $r->{disk_avg}, '==', ((60+30+60+100)/4), 'correct disk average';
cmp_ok $r->{ram_avg}, '==', ((8+4+16+4)/4), 'correct  ram avg';
cmp_ok $r->{filerio_avg}, '==', ((20+10+20+30)/4), 'correct filerio avg';
cmp_ok $r->{cpu_avg}, '==', ((2000+1000+3000+4000)/4), 'correct cpu avg';

$schema->raise_optimization_class();
done_testing();
