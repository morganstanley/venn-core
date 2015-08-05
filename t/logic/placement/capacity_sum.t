#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests=> 2;

use Venn::PlacementEngine;

my $schema = testschema();

lives_ok { $schema->deploy( { add_drop_table => 1, } ) } 'Schema deployed to sqlite';

bootstrap();

create_racks('ny', 'zy', 2, 2, 2, 2, [ 'dev' ], [ 1 ]);

my $placement = {
    resources => {
        filerio => 1,
        ram => 1,
        cpu => 1,
        disk => 1,
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
    },
    friendly => 'evmx123',
};

my $pengine = Venn::PlacementEngine->create('capacity', 'hosting', $placement, { schema => $schema });
my $capacity = $pengine->capacity();

my $correct = {
    'cpu' => 1408000,
    'disk' => 108592136,
    'filerio' => 68000,
    'capacity' => 68000,
    'ram' => 20971520,
};

is_deeply $capacity, $correct, 'capacity generating correct results';

done_testing();
