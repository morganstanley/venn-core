#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 5;

use Venn::PlacementEngine;

my $schema = testschema();
my ($pengine, $capacity);

lives_ok { $schema->deploy( { add_drop_table => 1, } ) } 'Schema deployed to sqlite';

bootstrap();

# ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $ownerid)
create_racks('ny', 'zy', 5, 2, 2, 2, [ 'dev' ], [ 1 ]);

#create some other racks that shouldn't matter, because of env, owner, building, or region
create_racks('ny', 'zy', 1, 2, 2, 2, [ 'qa' ], [ 1 ]);
create_racks('ny', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 2 ]);
create_racks('eu', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);
create_racks('ny', 'zz', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);

create_capability('real', 'A real testing', 0);

my $placement = {
    resources => {
        ram => 4, #4,
        cpu => 2000, #2000,
        filerio => 20, #20,
        disk => 60, #60,
    },
    attributes => {
        environment => 'qa',
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
};

$pengine = Venn::PlacementEngine->create('capacity', 'hosting', $placement, { schema => $schema });
$capacity = $pengine->capacity();
cmp_ok $capacity->{capacity}, '==', 352, 'correct capacity count';

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

$capacity = $pengine->capacity();
cmp_ok $capacity->{capacity}, '==', 351, 'correct capacity count';

#test capabilities
my $rs = $schema->resultset('Provider')->search();
while ( my $provrs = $rs->next() ) {
    $provrs->add_capability('real');
}

$placement->{attributes}->{capability}->{ram} = [ 'real' ];
$pengine = Venn::PlacementEngine->create('capacity', 'hosting', $placement, { schema => $schema });
$capacity = $pengine->capacity($placement);
cmp_ok $capacity->{capacity}, '==', 351, 'real capability correctly allows placement';

$placement->{attributes}->{capability}->{ram} = [ 'real', 'fake' ];
$pengine = Venn::PlacementEngine->create('capacity', 'hosting', $placement, { schema => $schema });
$capacity = $pengine->capacity($placement);
cmp_ok $capacity->{capacity}, '==', 0, 'fake capability correctly blocks placement';

done_testing();
