#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 15; #qw/ no_plan bail /;
use Data::Dumper;

my $schema = testschema();

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1, } );
    bootstrap();

    # ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner)
    create_racks('ny', 'zy', 5, 2, 2, 2, [ 'dev', 'prod' ], [ 1 ]);

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

my $placement = {
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
        continent => 'na',
        building => 'zy',
        campus => 'ny',
    },
    friendly => 'evmx123',
};

my %res_placement = (
    "provider.provider_owner.id"       => $placement->{attributes}->{owner},
    "provider.provider_environments.environment" => $placement->{attributes}->{environment},
    "provider.available_date"                    => { '<=' => time() },
    "provider.state_name"                        => 'active',
);

my $join = [
 { 'cluster' => { 'rack' => { 'filers' => [ 'disk', 'filerio' ] } } },
 'cpu',
];

my $rs = $schema->resultset('P_Memory_Cluster');

my $filerio_tmp_rs = $rs->related_resultset_chain(qw/ cluster rack filers filerio /);
my $filerio_rs = (ref $filerio_tmp_rs)->new($filerio_tmp_rs->result_source);

my $disk_tmp_rs = $rs->related_resultset_chain(qw/ cluster rack filers disk /);
my $disk_rs = (ref $disk_tmp_rs)->new($disk_tmp_rs->result_source);

my $cpu_tmp_rs = $rs->related_resultset_chain(qw/ cluster cpu /);
my $cpu_rs = (ref $cpu_tmp_rs)->new($cpu_tmp_rs->result_source);

my $ram_tmp_rs = $rs->related_resultset_chain(qw/ cluster ram /);
my $ram_rs = (ref $ram_tmp_rs)->new($ram_tmp_rs->result_source);

my $filerio_test = $rs->search_rs({ 'me.cluster_name' => 'zyecl1' },
                         {
                             '+columns' =>
                                 { test => $filerio_rs->get_correlated_assignment_total('filerio.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $filerio_test, '==', 30, "total filerio is correct";

my $disk_test = $rs->search_rs({ 'disk.share_name' => 'vmdisk1' },
                               {
                                   select => [qw/ disk.provider_id disk.share_name /],
                                   as => [qw/ disk_provider_id disk_share_name /],
                                   '+columns' => [
                                        { test => { coalesce => [ $disk_rs->get_correlated_assignment_total('disk.provider_id')->as_query, 0 ] } },
                                    ],
                                    join => $join,
                         })
                     ->get_column('test')
                     ->first;

cmp_ok $disk_test, '==', 90, "total disk is correct";

my $disk_test2 = $rs->search_rs({ 'disk.share_name' => 'vmdisk2' },
                               {
                                   select => [qw/ disk.provider_id disk.share_name /],
                                   as => [qw/ disk_provider_id disk_share_name /],
                                   '+columns' => [
                                        { test => { coalesce => [ $disk_rs->get_correlated_assignment_total('disk.provider_id')->as_query, 0 ] } },
                                    ],
                                    join => $join,
                         })
                     ->get_column('test')
                     ->first;

cmp_ok $disk_test2, '==', 0, "total disk is correct";

my $ram_test = $rs->search_rs({ 'me.cluster_name' => 'zyecl1' },
                         {
                             '+columns' =>
                                 { test => $ram_rs->get_correlated_assignment_total('me.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $ram_test, '==', 12, "total ram is correct";

my $cpu_test = $rs->search_rs({ 'cpu.cluster_name' => 'zyecl1' },
                         {
                             '+columns' =>
                                 { test => $cpu_rs->get_correlated_assignment_total('cpu.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $cpu_test, '==', 3000, "total cpu is correct";

my $filerioavg_test = $rs->search_rs({ 'filerio.filer_name' => 'nyn1' },
                         {
                             '+columns' =>
                                 { test => $filerio_rs->get_correlated_average_assignment('filerio.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $filerioavg_test, '==', 15, "avg filerio is correct";

my $diskavg_test = $rs->search_rs({ 'disk.share_name' => 'vmdisk1' },
                               {
                                   '+columns' =>
                                   { test => $disk_rs->get_correlated_average_assignment('disk.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $diskavg_test, '==', 45, "avg disk is correct";

my $diskavg_test2 = $rs->search_rs({ 'disk.share_name' => 'vmdisk2' },
                               {
                                   '+columns' =>
                                   { test => { coalesce => [ $disk_rs->get_correlated_average_assignment('disk.provider_id')->as_query, 0 ] } },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $diskavg_test2, '==', 0, "avg disk is correct for vmdisk2";


my $ramavg_test = $rs->search_rs({ 'me.cluster_name' => 'zyecl1' },
                         {
                             '+columns' =>
                                 { test => $ram_rs->get_correlated_average_assignment('me.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $ramavg_test, '==', 6, "avg ram is correct";

my $cpuavg_test = $rs->search_rs({ 'cpu.cluster_name' => 'zyecl1' },
                         {
                             '+columns' =>
                                 { test => $cpu_rs->get_correlated_average_assignment('cpu.provider_id')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

cmp_ok $cpuavg_test, '==', 1500, "avg cpu is correct";

my $filerio_una_test = $rs->search_rs( { 'filers.filer_name' => 'nyn1' },
                         {
                             '+columns' =>
                                 { test => $filerio_rs->get_correlated_unassigned('filerio.provider_id', 'hosting')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first ;

#nyn1 has 17000 total, 30 used = 16970
cmp_ok $filerio_una_test, '==', 16970, "unassigned filerio is correct";

my $disk_una_test = $rs->search_rs({'disk.share_name' => 'vmdisk1' },
                               {
                                   '+columns' =>
                                   { test => $disk_rs->get_correlated_unassigned('disk.provider_id', 'hosting')->as_query }, join => $join,
                         })
    ->get_column('test')
    ->first;

#90 assigned. 13574017 total.  13573927 remaining.
cmp_ok  $disk_una_test, '==', 13573927, "unassigned disk is correct";

my $disk_una_test2 = $rs->search_rs({'disk.share_name' => 'vmdisk2' },
                               {
                                   '+columns' =>
                                   { test => $disk_rs->get_correlated_unassigned('disk.provider_id', 'hosting')->as_query }, join => $join,
                         })
    ->get_column('test')
    ->first;

# #vmdisk2 has 13574017 total and none assigned.
cmp_ok $disk_una_test2, '==', 13574017, "unassigned disk is correct for vmdisk2";


my $ram_una_test = $rs->search_rs( {'me.cluster_name' => 'zyecl1'},
                         {
                             '+columns' =>
                                 { test => $ram_rs->get_correlated_unassigned('me.provider_id', 'hosting')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;
#zyecl1 12 assigned. 5242880 total. 5242868 left.
cmp_ok $ram_una_test, '==', 5242868, "unassigned ram is correct";

my $cpu_una_test = $rs->search_rs({'cpu.cluster_name' => 'zyecl1'},
                         {
                             '+columns' =>
                                 { test => $cpu_rs->get_correlated_unassigned('cpu.provider_id', 'hosting')->as_query },
                             join => $join,
                         })
    ->get_column('test')
    ->first;

#3000 used. 352000 total. 349000 left.
cmp_ok $cpu_una_test, '==', 349000, "unassigned cpu is correct";

done_testing();
