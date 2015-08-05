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

lives_ok { $schema->deploy( { add_drop_table => 1, } ) } 'Schema deployed to sqlite';

bootstrap();

create_racks('ny', 'zy', 2, 2, 2, 2, [ 'dev' ], [ 1 ]);

$schema->resultset('AssignmentGroup')->create({
    assignmentgroup_type_name => 'hosting',
    identifier => 'A18B46FA-BE5C-11E3-8F6F-11687F0910EB',
});

my $placement = {
    resources => {
        filerio => 1,
        ram => 20000,
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

# Compute capacity before any allocation
{
    my $capacity = $pengine->capacity();

    my $correct = {
        'cpu' => 1408000,
        'disk' => 108592136,
        'filerio' => 68000,
        'capacity' => 1048,
        'ram' => 1048
    };

    is_deeply $capacity, $correct, 'capacity generating correct results';
}

# Exhaust an ram provider entirely
{
    $schema->resultset('Assignment')->create({
        provider_id => 7,
        assignmentgroup_id => 1,
        size => 5242880,
        committed => 1,
    });

    my $capacity = $pengine->capacity();

    my $correct = {
        'cpu' => 1408000,
        'disk' => 108592136,
        'filerio' => 68000,
        'capacity' => 786,
        'ram' => 786
    };

    is_deeply $capacity, $correct, 'capacity generating correct results';
}

# Over-allocate the same ram resource, capacity should not change
{
    $schema->resultset('Assignment')->create({
        provider_id => 7,
        assignmentgroup_id => 1,
        size => 5242880,
        committed => 1,
    });

    my $capacity = $pengine->capacity();

    my $correct = {
        'cpu' => 1408000,
        'disk' => 108592136,
        'filerio' => 68000,
        'capacity' => 786,
        'ram' => 786
    };

    is_deeply $capacity, $correct, 'capacity generating correct results';
}

done_testing();
