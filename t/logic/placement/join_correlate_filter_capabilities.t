#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests=> 17; #qw/ no_plan bail /;

use Venn::PlacementEngine;

my $schema = testschema();
$schema->lower_optimization_class(1);

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

    create_capability('real', 'A real testing', 0);
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
        continent => 'na',
        building => 'zy',
    },
    friendly => 'evmx123',
);


#test capability
my $rs = $schema->resultset('Provider')->search();
while ( my $provrs = $rs->next() ) {
    $provrs->add_capability('real');
}

$placement{attributes}->{capability}->{ram} = [ 'real' ];

my $placement_engine = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});

my $r = $placement_engine->join_correlate_filter({test_columns => 1})->as_hash->first;

is $r->{filerio_provider_id}, 1, 'correct filerio provider id';
is $r->{filerio_filer_name}, 'nyn1', 'correct filerio filer name';
cmp_ok $r->{filerio_total}, '==', 30, 'correct filerio assigned total';
cmp_ok $r->{filerio_unassigned}, '==', 16970, 'correct filerio unassigned total';

is $r->{ram_provider_id}, 7, 'correct ram provider id';
is $r->{cluster_name}, 'zyecl1', 'correct ram cluster name';
cmp_ok $r->{ram_total}, '==', 12, 'correct ram assigned total';
cmp_ok $r->{ram_unassigned}, '==', ((256 * 1024 * 20) - 12), 'correct ram unassigned total';

is $r->{cpu_provider_id}, 8, 'correct cpu provider id';
is $r->{cpu_cluster_name}, 'zyecl1', 'correct cpu cluster name';
cmp_ok $r->{cpu_total}, '==', 3000, 'correct cpu total assigned';
cmp_ok $r->{cpu_unassigned}, '==',  349000, 'correct cpu unassigned total';

is $r->{disk_provider_id}, 2, 'correct disk provider id';
is $r->{disk_share_name}, 'vmdisk1', 'correct disk filer name';
cmp_ok $r->{disk_total}, '==',  90, 'correct disk total assigned';
cmp_ok $r->{disk_unassigned}, '==', 13573927, 'correct disk unassigned total';

$placement{attributes}->{capability}->{ram} = [ 'real', 'fake' ];
$placement{attributes}->{capability}->{cpu} = [ 'real', 'fake' ];
$placement{attributes}->{capability}->{filerio} = [ 'real', 'fake' ];
$placement{attributes}->{capability}->{disk} = [ 'real', 'fake' ];

$placement_engine = Venn::PlacementEngine->create('random', 'hosting', \%placement, {
    schema  => $schema,
});

$r = $placement_engine->join_correlate_filter()->as_hash->first;

is $r, undef, 'no placement with fake capability';

done_testing();

1;
