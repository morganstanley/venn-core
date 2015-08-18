#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 60;
use Catalyst::Test 'Venn';
use Data::Dumper;
use HTTP::Request::Common qw( GET PUT POST DELETE );
use JSON::XS;

my $schema = testschema();

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1 } );
    bootstrap();

    # ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner)
    create_racks('ny', 'zy', 5, 2, 2, 2, [ 'dev' ], [ 1 ]);

    #create some other racks that shouldn't matter, because of env, owner, building, or region
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'qa' ], [ 1 ]);
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 2 ]);
    create_racks('ln', 'zy', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);
    create_racks('ny', 'zz', 1, 2, 2, 2, [ 'dev' ], [ 1 ]);

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

$schema->lower_optimization_level();

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

my %placement = (
    assignmentgroup_type => 'hosting',
    resources => {
        ram => 16, # avg should be 8, so should be above avg. pick this one second (desc).
        cpu => 1000, #avg should be 2500, should be way below. pick this one first (ascending).
        filerio => 20, #avg should be 20. this should be last in the sort order (asc).
        disk => 62, #avg should be 62.5. should be 3rd (asc)
    },
    attributes => {
        environment => 'dev',
        owner => [1],
    },
    location => {
        campus => 'ny',
        building => 'zy',
    },
    friendly => 'evmx123',
);

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

# POST place test
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

    # warn "Received: " . $place_resp->content . "\n";
    my $result = decode_json($place_resp->content);
    $identifier = $result->{assignmentgroup}->{identifier};

    my $location = $result->{placement_location};
    my $commit_group_id = $result->{commit_group_id};

    is $place_resp->code, 201, "Placed";
    is int $location->{cpu_provider_id}, 10, 'correct cpu provider id';
    is int $location->{ram_provider_id}, 9, 'correct ram provider id';
    is int $location->{filerio_provider_id}, 1, 'correct filerio provider id';
    is int $location->{disk_provider_id}, 2, 'correct disk provider id';

    # Verify assignments haven't been committed yet
    my $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id
    });
    while (my $assignment = $assignments->next) {
        is int $assignment->committed, 0, 'Assignment not committed yet';
    }

    # Commit the placement
    my $commit_uri = "api/v1/commit_group/$commit_group_id";
    my $commit_resp = request(
        POST $commit_uri,
    );
    my $commit_result = decode_json($commit_resp->content);

    # Verify assignments have been committed
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    while (my $assignment = $assignments->next) {
        cmp_ok $assignment->committed, '>', 0, 'Assignment committed';
    }
    ok $commit_resp->is_success, "Assignments committed";
}

# POST resize the above placement
{
    my $resize_uri = "/api/v1/resize/$identifier";
    my $resources = {
        ram => 20,
        cpu => 1000,
        filerio => 20,
        disk => 70,
    };
    my $resize_resp = request(
        POST $resize_uri,
        Content_Type => 'application/json',
        Content      => encode_json($resources),
    );

    my $result = decode_json($resize_resp->content);
    my $commit_group_id = $result->{commit_group_id};
    ok $resize_resp->is_success, 'Resize successful';

    # Verify assignments have been adjusted correctly for resize
    my $assignments = _get_grouped_assignments($identifier);
    while (my $assignment = $assignments->next) {
        is int $assignment->get_column('total'),
            $resources->{$assignment->get_column('providertype_name')},
            'Assignment adjusted for resize';
    }

    # Verify resize assignments haven't been committed yet
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id
    });
    while (my $assignment = $assignments->next) {
        is int $assignment->committed, 0, 'Assignment not committed yet';
    }

    # Commit the resize
    my $commit_uri = "api/v1/commit_group/$commit_group_id";
    my $commit_resp = request(
        POST $commit_uri,
    );
    my $commit_result = decode_json($commit_resp->content);

    # Verify assignments have been committed
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    while (my $assignment = $assignments->next) {
        cmp_ok $assignment->committed, '>', 0, 'Assignment committed';
    }
    ok $commit_resp->is_success, "Assignments committed";
}

# POST unassign the above placement
{
    my $unassign_uri = "/api/v1/unassign/$identifier";
    my $unassign_resp = request(
        POST $unassign_uri,
    );

    my $result = decode_json($unassign_resp->content);
    my $commit_group_id = $result->{commit_group_id};
    ok $unassign_resp->is_success, 'Unassignment successful';

    # Verify assignments for assignmentgroup have been zeroed
    my $assignments = _get_grouped_assignments($identifier);
    while (my $assignment = $assignments->next) {
        is int $assignment->get_column('total'), 0, 'Assignment deducted';
    }

    # Verify assignments have been committed immediately
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id
    });
    while (my $assignment = $assignments->next) {
        ok $assignment->committed > 0, 'Assignment committed';
    }
}

# POST cancel_commit_group test + DELETE
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
    my $commit_group_id = $result->{commit_group_id};

    # Cancel the commit group
    my $commit_uri = "api/v1/commit_group/$commit_group_id";
    my $commit_resp = request(
        DELETE $commit_uri,
    );
    my $commit_result = decode_json($commit_resp->content);

    # Verify assignments have been deleted
    my $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    my $count = 0;
    while (my $assignment = $assignments->next) {
        $count += 1;
    }
    is int $count, 0, "Assignments deleted from cancel_commit_group";
}

# POST cancel_commit_group double DELETE test
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
    my $commit_group_id = $result->{commit_group_id};

    # Cancel the commit group
    my $commit_uri = "api/v1/commit_group/$commit_group_id";
    my $commit_resp = request(
        DELETE $commit_uri,
    );
    my $commit_result = decode_json($commit_resp->content);

    # Verify assignments have been deleted
    my $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    my $count = 0;
    while (my $assignment = $assignments->next) {
        $count += 1;
    }
    is int $count, 0, "Assignments deleted from cancel_commit_group";

    # Cancel the commit group AGAIN
    my $double_del_resp = request(
        DELETE $commit_uri,
    );
    is $double_del_resp->code, 404, 'Commit group not found';
}

# POST place another
{
    my $agt = $placement{assignmentgroup_type};
    my $strategy = "biggest_outlier";
    my $uri = "/api/v1/place/$agt/$strategy";

    my $place_resp = request(
        POST $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%placement),
    );

    # warn "Received: " . $place_resp->content . "\n";
    my $result = decode_json($place_resp->content);
    $identifier = $result->{assignmentgroup}->{identifier};

    my $location = $result->{placement_location};
    my $commit_group_id = $result->{commit_group_id};

    is $place_resp->code, 201, "Placed";

    # Verify assignments haven't been committed yet
    my $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id
    });
    while (my $assignment = $assignments->next) {
        is int $assignment->committed, 0, 'Assignment not committed yet';
    }

    # Commit the placement
    my $commit_uri = "api/v1/commit_group/$commit_group_id";
    my $commit_resp = request(
        POST $commit_uri,
    );
    my $commit_result = decode_json($commit_resp->content);

    # Verify assignments have been committed
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    while (my $assignment = $assignments->next) {
        cmp_ok $assignment->committed, '>', 0, 'Assignment committed';
    }
    ok $commit_resp->is_success, "Assignments committed";
}

# POST unassign the above placement without commit
{
    my $unassign_uri = "/api/v1/unassign/$identifier";
    my $unassign_resp = request(
        POST $unassign_uri,
        Content_Type => 'application/json',
        Content      => encode_json( { commit => 0 } )
    );

    my $result = decode_json($unassign_resp->content);
    my $commit_group_id = $result->{commit_group_id};
    ok $unassign_resp->is_success, 'Unassignment successful';

    # Verify assignments for assignmentgroup have been zeroed
    my $assignments = _get_grouped_assignments($identifier);
    my $i = 0;
    while (my $assignment = $assignments->next) {
        is int $assignment->get_column('total'), 0, 'Assignment deducted';
        $i++;
    }
    is $i, 0, '0 assignments returned';

    # Verify unassign assignments have been committed immediately
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    is int $assignments->count, 4, '4 assignments returned';
    while (my $assignment = $assignments->next) {
        is $assignment->committed, 0, 'Assignment not committed';
    }

    # Commit the placement
    my $commit_uri = "api/v1/commit_group/$commit_group_id";
    my $commit_resp = request(
        POST $commit_uri,
    );
    my $commit_result = decode_json($commit_resp->content);

    # Verify assignments have been committed
    $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id,
    });
    while (my $assignment = $assignments->next) {
        cmp_ok $assignment->committed, '>', 0, 'Assignment committed';
    }
    ok $commit_resp->is_success, "Assignments committed";
}

# POST place test with immediate commit
{
    $placement{commit} = 1; # commit it immediately
    my $agt = $placement{assignmentgroup_type};
    my $strategy = "biggest_outlier";
    my $uri = "/api/v1/place/$agt/$strategy";

    my $place_resp = request(
        POST $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%placement),
    );

    # warn "Received: " . $place_resp->content . "\n";
    my $result = decode_json($place_resp->content);
    $identifier = $result->{assignmentgroup}->{identifier};

    my $commit_group_id = $result->{commit_group_id};

    # Verify assignments haven't been committed yet
    my $assignments = $schema->resultset('Assignment')->search({
        commit_group_id => $commit_group_id
    });
    while (my $assignment = $assignments->next) {
        is int $assignment->committed, 1, 'Assignment committed';
    }
}

# POST place test with a wrong resource specified (foobar)
{
    my %wrong_placement = %placement;
    $wrong_placement{resources} = {
        %{$placement{resources}},
        foobar => 42,
    };
    my $agt = $wrong_placement{assignmentgroup_type};
    my $strategy = "biggest_outlier";
    my $uri = "/api/v1/place/$agt/$strategy";

    my $place_resp = request(
        POST $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%wrong_placement),
    );

    my $result = decode_json($place_resp->content);
    ok $result->{error} =~ /error.*Not a resource: foobar/, 'Wrong request resource identified and refused';
}

# POST place test with an unbound resource specified (hostram)
{
    my %wrong_placement = %placement;
    $wrong_placement{resources} = {
        %{$placement{resources}},
        hostram => 42,
    };
    my $agt = $wrong_placement{assignmentgroup_type};
    my $strategy = "biggest_outlier";
    my $uri = "/api/v1/place/$agt/$strategy";

    my $place_resp = request(
        POST $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%wrong_placement),
    );

    my $result = decode_json($place_resp->content);
    ok $result->{error} =~ /error.*Invalid request resource/, 'Unbound request resource identified and refused';
}


# Retrieve assignments for an assignmentgroup
sub _get_grouped_assignments {
    my ($id) = @_;

    my $assignmentgroup = $schema->resultset('AssignmentGroup')->search({
        identifier => $id,
    })->first;

    return $schema->resultset('Assignment')->group_by_assignmentgroup_id($assignmentgroup->assignmentgroup_id, undef, undef);
}
