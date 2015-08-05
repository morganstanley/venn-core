#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 130;
use Catalyst::Test 'Venn';
use Data::Dumper;
use HTTP::Request::Common qw( GET PUT POST DELETE );
use JSON::XS;

$ENV{VENN_TEST} = 1;
$ENV{VENN_IN_MEMORY} //= 1;

use Venn::Schema;

my $schema = testschema();

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1 } );
    bootstrap();

    #($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner)
    create_racks('ny', 'zy', 5, 2, 2, 2, [ 'dev' ], [ 1 ]);
    create_racks('ny', 'yy', 1, 1, 1, 1, [ 'dev' ], [ 1 ]);
    create_racks('mt', 'zz', 1, 1, 1, 1, [ 'qa' ], [ 2 ]);

=begin comment

    Rack: zy1
    Filer: nyn1
    Share: vmdisk1
    Share: vmdisk2
    Filer: nyn2
    Share: vmdisk3
    Share: vmdisk4
    Cluster: zyecl1
    Cluster: zyecl2
    ==================================
    Rack: zy2
    Filer: nyn3
    Share: vmdisk5
    Share: vmdisk6
    Filer: nyn4
    Share: vmdisk7
    Share: vmdisk8
    Cluster: zyecl3
    Cluster: zyecl4
    ==================================
    Rack: zy3
    Filer: nyn5
    Share: vmdisk9
    Share: vmdisk10
    Filer: nyn6
    Share: vmdisk11
    Share: vmdisk12
    Cluster: zyecl5
    Cluster: zyecl6
    ==================================
    Rack: zy4
    Filer: nyn7
    Share: vmdisk13
    Share: vmdisk14
    Filer: nyn8
    Share: vmdisk15
    Share: vmdisk16
    Cluster: zyecl7
    Cluster: zyecl8
    ==================================
    Rack: zy5
    Filer: nyn9
    Share: vmdisk17
    Share: vmdisk18
    Filer: nyn10
    Share: vmdisk19
    Share: vmdisk20
    Cluster: zyecl9
    Cluster: zyecl10
    =================================
    Rack: zz6
    Filer: mtn11
    Share: vmdisk21
    Cluster: zzecl11
    =================================
    Rack: zz7
    Filer: mtn12
    Share: vmdisk22
    Cluster: zzecl122

=end comment

=cut
}

$schema->lower_optimization_level();

my %placement = (
    assignmentgroup_type => 'hosting',
    resources => {
        ram => 16,
        cpu => 1000,
        filerio => 20,
        disk => 62,
    },
    attributes => {
        environment => 'dev',
        capability => {},
        owner => [1],
    },
    location => {
        campus => 'ny',
        building => 'zy',
    },
    friendly_lookup => 'evmx123',
);

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

# place a guest
my $identifier;
{
    my $agt = $placement{assignmentgroup_type};
    my $strategy = "biggest_outlier";
    my $uri = "/api/v1/place/$agt/$strategy";

    my $place_resp = request(
        POST $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%placement),
    );
    my $result = decode_json($place_resp->content);
    $identifier = $result->{assignmentgroup}->{identifier};

    my $location = $result->{placement_location};

    is $place_resp->code, 201, "Placed";
    is int $location->{cpu_provider_id}, 8, 'correct cpu provider id';
    is int $location->{ram_provider_id}, 7, 'correct ram provider id';
    is int $location->{filerio_provider_id}, 1, 'correct filerio provider id';
    is int $location->{disk_provider_id}, 2, 'correct disk provider id';
}

# migrate place - specify 2 resources on the same rack
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        manual_placement => {
            disk => 'vmdisk20',
            ram => 'zyecl10',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });

    ok $http_resp->is_success, "migrate call successful";

    # Validate old provider has been zeroed
    is int _get_assignment_total({provider_id => 8})->get_column('total'), 0, 'cpu provider_id zeroed';
    is int _get_assignment_total({provider_id => 7})->get_column('total'), 0, 'ram provider_id zeroed';
    is int _get_assignment_total({provider_id => 2})->get_column('total'), 0, 'disk provider_id zeroed';

    _validate_resource_size($identifier);

    # Validate assignments have been properly placed
    is int _get_provider_total($identifier, 'disk', 'vmdisk20'), 62, 'disk moved to vmdisk20';
    is int _get_provider_total($identifier, 'ram', 'zyecl10'), 16, 'ram moved to zyecl10';
    is int _get_provider_total($identifier, 'cpu', 'zyecl10'), 1000, 'cpu moved to zyecl10';
}

# migrate place - specify 2 resources on incompatible racks (should fail)
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        manual_placement => {
            disk => 'vmdisk3',
            ram => 'zyecl3',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok !$http_resp->is_success, 'migration not successful due to incompatible racks';

    _validate_resource_size($identifier);

    # Validate assignments have not changed
    is int _get_provider_total($identifier, 'disk', 'vmdisk20'), 62, 'disk stays at vmdisk20';
    is int _get_provider_total($identifier, 'ram', 'zyecl10'), 16, 'ram stays at zyecl10';
    is int _get_provider_total($identifier, 'cpu', 'zyecl10'), 1000, 'cpu stays atzyecl10';
}

# migrate_specific - specify 1 resource on same rack
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'specific', {
        manual_placement => {
            disk => 'vmdisk19',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok $http_resp->is_success, 'migrate_specific to share successful';

    _validate_resource_size($identifier);

    # Validate share has changed to vmdisk19
    is int _get_provider_total($identifier, 'disk', 'vmdisk20'), 0, 'assignment deducted from vmdisk20';
    is int _get_provider_total($identifier, 'disk', 'vmdisk19'), 62, 'disk moved to vmdisk19';

    # Validate other assignments have not changed
    is int _get_provider_total($identifier, 'ram', 'zyecl10'), 16, 'ram stays at zyecl10';
    is int _get_provider_total($identifier, 'cpu', 'zyecl10'), 1000, 'cpu stays at zyecl10';
}

# migrate specific - specify 1 resource on different rack (should fail)
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'specific', {
        manual_placement => {
            disk => 'vmdisk1',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok !$http_resp->is_success, 'migrate_specific to share on different rack fail';

    _validate_resource_size($identifier);

    # Validate assignments have not changed
    is int _get_provider_total($identifier, 'disk', 'vmdisk19'), 62, 'disk stays at vmdisk19';
    is int _get_provider_total($identifier, 'ram', 'zyecl10'), 16, 'ram stays at zyecl10';
    is int _get_provider_total($identifier, 'cpu', 'zyecl10'), 1000, 'cpu stays at zyecl10';
}

# migrate specific - specify 2 resources on incompatible racks (should fail)
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'specific', {
        manual_placement => {
            disk => 'vmdisk3',
            ram => 'zyecl3',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok !$http_resp->is_success, 'migration not successful due to incompatible racks';

    _validate_resource_size($identifier);

    # Validate assignments have not changed
    is int _get_provider_total($identifier, 'disk', 'vmdisk19'), 62, 'disk stays at vmdisk19';
    is int _get_provider_total($identifier, 'ram', 'zyecl10'), 16, 'ram stays at zyecl10';
    is int _get_provider_total($identifier, 'cpu', 'zyecl10'), 1000, 'cpu stays at zyecl10';
}

# migrate specific - specify all resources on the same rack
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'specific', {
        manual_placement => {
            disk => 'vmdisk7',
            ram => 'zyecl3',
            cpu => 'zyecl3',
            filerio => 'nyn4',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok $http_resp->is_success, 'migration successful';

    _validate_resource_size($identifier);

    # Validate previous providers udisksigned
    is int _get_provider_total($identifier, 'disk', 'vmdisk19'), 0, 'assignment deducted from vmdisk19';
    is int _get_provider_total($identifier, 'ram', 'zyecl10'), 0, 'assignment dedeucted for zyecl10';
    is int _get_provider_total($identifier, 'cpu', 'zyecl10'), 0, 'assignment dedeucted for zyecl10';

    # Validate assignments have changed to correct providers
    is int _get_provider_total($identifier, 'disk', 'vmdisk7'), 62, 'disk moved to vmdisk7';
    is int _get_provider_total($identifier, 'ram', 'zyecl3'), 16, 'ram moved to zyecl3';
    is int _get_provider_total($identifier, 'cpu', 'zyecl3'), 1000, 'cpu moved to zyecl3';
    is int _get_provider_total($identifier, 'filerio', 'nyn4'), 20, 'filerio moved to nyn4';
}

# migrate place - specify 1 resource on a separate rack
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        manual_placement => {
            disk => 'vmdisk20',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok $http_resp->is_success, 'migration successful';

    _validate_resource_size($identifier);

    # Validate previous providers udisksigned
    is int _get_provider_total($identifier, 'disk', 'vmdisk7'), 0, 'assignment deducted from vmdisk7';
    is int _get_provider_total($identifier, 'ram', 'zyecl3'), 0, 'assignment deducted from zyecl3';
    is int _get_provider_total($identifier, 'cpu', 'zyecl3'), 0, 'assignment deducted from zyecl3';
    is int _get_provider_total($identifier, 'filerio', 'nyn4'), 0, 'assignment dedeucted from nyn4';

    # Validate assignment for disk has changed to the correct provider
    is int _get_provider_total($identifier, 'disk', 'vmdisk20'), 62, 'disk moved to vmdisk20';
}

# migrate place - specify 1 resource in incompatible building (should fail)
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        manual_placement => {
            disk => 'vmdisk20',
        },
        location => {
            building => 'yy',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok !$http_resp->is_success, 'migration unsuccessful due to incompatible region';

    _validate_resource_size($identifier);
}

# migrate place - specify region change (should fail because env and eonid are different)
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        location => {
            campus => 'mt',
        },
        attributes => {
            environment => 'dev',
            capability => {},
            owner => [1],
        },
    });
    ok !$http_resp->is_success, 'migration unsuccessful due to incompatible region';

    _validate_resource_size($identifier);
}

# migrate place - specify region with correct eonid and env
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        attributes => {
            owner => [ 2 ],
            environment => 'qa',
        },
        location => {
            campus => 'mt',
        },
    });
    ok $http_resp->is_success, 'migration to new region successful';

    _validate_resource_size($identifier);

    # Validate assignments moved to new region
    is int _get_provider_total($identifier, 'disk', 'vmdisk22'), 62, 'disk moved to vmdisk21';
    is int _get_provider_total($identifier, 'ram', 'zzecl12'), 16, 'ram moved to zzecl11';
    is int _get_provider_total($identifier, 'cpu', 'zzecl12'), 1000, 'cpu moved to zzecl11';
    is int _get_provider_total($identifier, 'filerio', 'mtn12'), 20, 'filerio moved to mtn11';
}

# Introduce explicit capability on resources to migrate to
{
    create_capability('explicit_a', '', 1);
    create_capability('explicit_b', '', 1);
    create_capability('non_explicit_a', '', 0);

    add_capability_to_provider_by_name('zyecl1', 'explicit_a', 'cpu');
    add_capability_to_provider_by_name('zyecl1', 'explicit_a', 'ram');
    add_capability_to_provider_by_name('vmdisk1', 'explicit_a', 'disk');
    add_capability_to_provider_by_name('nyn1', 'explicit_a', 'filerio');

    add_capability_to_provider_by_name('zyecl1', 'explicit_b', 'cpu');
    add_capability_to_provider_by_name('zyecl1', 'explicit_b', 'ram');
    add_capability_to_provider_by_name('vmdisk1', 'explicit_b', 'disk');
    add_capability_to_provider_by_name('nyn1', 'explicit_b', 'filerio');

    add_capability_to_provider_by_name('zyecl1', 'non_explicit_a', 'cpu');
    add_capability_to_provider_by_name('zyecl1', 'non_explicit_a', 'ram');
    add_capability_to_provider_by_name('vmdisk1', 'non_explicit_a', 'disk');
    add_capability_to_provider_by_name('nyn1', 'non_explicit_a', 'filerio');

    # Don't specificy capability, should fail
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'specific', {
        attributes => {
            owner => [ 1 ],
            environment => 'dev',
            capability => {
                cpu => [ 'explicit_a' ],
                ram => [ 'explicit_a' ],
                disk => [ 'explicit_a' ],
                filerio => [ 'explicit_a' ],
            },
        },
        location => {
            region => 'na',
        },
        manual_placement => {
            cpu => 'zyecl1',
            ram => 'zyecl1',
            disk => 'vmdisk1',
            filerio => 'nyn1',
        },
    });
    ok !$http_resp->is_success, 'migration unsuccessful due to unspecificed explicit capability';
    _validate_resource_size($identifier);

    # Specify all explicit capability
    ($migrate_resp, $http_resp) = _migrate($identifier, 'specific', {
        attributes => {
            owner => [ 1 ],
            environment => 'dev',
            capability => {
                cpu => [ 'explicit_a', 'explicit_b' ],
                ram => [ 'explicit_a', 'explicit_b' ],
                disk => [ 'explicit_a', 'explicit_b' ],
                filerio => [ 'explicit_a', 'explicit_b' ],
            },
        },
        location => {
            region => 'na',
        },
        manual_placement => {
            cpu => 'zyecl1',
            ram => 'zyecl1',
            disk => 'vmdisk1',
            filerio => 'nyn1',
        },
    });
    ok $http_resp->is_success, 'migration successful with explicit capability';
    _validate_resource_size($identifier);

    # Validate assignments moved
    is int _get_provider_total($identifier, 'disk', 'vmdisk1'), 62, 'disk moved to vmdisk1';
    is int _get_provider_total($identifier, 'ram', 'zyecl1'), 16, 'ram moved to zyecl1';
    is int _get_provider_total($identifier, 'cpu', 'zyecl1'), 1000, 'cpu moved to zyecl1';
    is int _get_provider_total($identifier, 'filerio', 'nyn1'), 20, 'filerio moved to nyn1';
}

# Migrate to another rack
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        attributes => {
            owner => [ 2 ],
            environment => 'qa',
        },
        location => {
            rack_name => 'zz7',
        },
    });
    ok $http_resp->is_success, 'migration to new rack successful';

    _validate_resource_size($identifier);

    # Validate assignments moved to new rack
    is int _get_provider_total($identifier, 'disk', 'vmdisk22'), 62, 'disk moved to vmdisk21';
    is int _get_provider_total($identifier, 'ram', 'zzecl12'), 16, 'ram moved to zzecl11';
    is int _get_provider_total($identifier, 'cpu', 'zzecl12'), 1000, 'cpu moved to zzecl11';
    is int _get_provider_total($identifier, 'filerio', 'mtn12'), 20, 'filerio moved to mtn11';
}

# Migrate to another rack with capability (capability created from previous test)
{
    my ($migrate_resp, $http_resp) = _migrate($identifier, 'place', {
        attributes => {
            owner => [ 1 ],
            environment => 'dev',
            capability => {
                cpu => [ 'explicit_a', 'explicit_b' ],
                ram => [ 'explicit_a', 'explicit_b' ],
                disk => [ 'explicit_a', 'explicit_b' ],
                filerio => [ 'explicit_a', 'explicit_b' ],
            },
        },
        location => {
            rack_name => 'zy1',
        },
    });
    ok $http_resp->is_success, 'migration to new region successful';

    _validate_resource_size($identifier);

    # Validate assignments moved
    is int _get_provider_total($identifier, 'disk', 'vmdisk1'), 62, 'disk moved to vmdisk1';
    is int _get_provider_total($identifier, 'ram', 'zyecl1'), 16, 'ram moved to zyecl1';
    is int _get_provider_total($identifier, 'cpu', 'zyecl1'), 1000, 'cpu moved to zyecl1';
    is int _get_provider_total($identifier, 'filerio', 'nyn1'), 20, 'filerio moved to nyn1';
}

done_testing();

#========== Subroutines ==========

# Migrate resources for identifier
sub _migrate {
    my ($id, $type, $data) = @_;

    my $uri = "api/v1/migrate_$type/$id";

    # Send migrate request
    my $migrate_resp = request(
        POST $uri,
        Content_Type => 'application/json',
        Content => encode_json($data),
    );

    my $content = decode_json($migrate_resp->content);

    # Commit the migration
    if ($migrate_resp->is_success) {
        my $commit_uri = "api/v1/commit_group/$id";
        my $commit_resp = request(
            POST $commit_uri,
        );
        my $commit_result = decode_json($commit_resp->content);

        ok $migrate_resp->is_success, 'Commit successful for migration';
    }

    return ($content, $migrate_resp);
}

# Retrieve total assignments for a provider_id
sub _get_assignment_total {
    my ($filter) = @_;

    return $schema->resultset('Assignment')->search(
        $filter,
        {
            select      => [ {sum => 'me.size'} ],
            as          => [ 'total' ],
        },
    )->first;
}

# Retrieve total assignment for an assignment group and provider
sub _get_provider_total {
    my ($id, $providertype_name, $provider_name) = @_;

    my $assignmentgroup = $schema->resultset('AssignmentGroup')->find_by_identifier($id);

    my $provider_class = $schema->provider_mapping->{$providertype_name}->{source};
    my $provider = $schema->resultset($provider_class)->find_by_primary_field($provider_name);

    return $schema->resultset('Assignment')->get_provider_total(
        $assignmentgroup->assignmentgroup_id,
        $provider->provider_id,
    )->single()->get_column('total');
}

# Verify size of resources for each providertype_name matches placement
sub _validate_resource_size {
    my ($id) = @_;

    my $ag = $schema->resultset('AssignmentGroup')->find_by_identifier($id);

    # Validate size of resource assignments is correct
    my $assignments = $schema->resultset('Assignment')->group_by_assignmentgroup_id($ag->assignmentgroup_id);
    while (my $assignment = $assignments->next) {
        my $providertype_name = $assignment->get_column('providertype_name');
        is int $assignment->get_column('total'),
            $placement{resources}->{$providertype_name},
            'Size for ' . $providertype_name  . ' is correct',
    }

    return;
}
