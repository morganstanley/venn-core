#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 17;
use Catalyst::Test 'Venn';
use Data::Dumper;
use HTTP::Request::Common qw( GET PUT POST DELETE );
use JSON::XS;

my $schema = testschema();

my $cluster_name = "cluster$$";

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1 } );

    bootstrap();

    #my ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner) = @_;
    create_racks('ny', 'ny', 2, 2, 2, 2, [ 'dev' ], [ 1 ]);
}

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

my $uri = "/api/v1/assignmentgroup";

# these are zlight by default
assign('evmzy1', 1, [ 8, 8 ], 1);
assign('evmzy2', 1, [ 16, -8 ], 1);
assign('evmzy3', 1, [ 32, -24 ], 1);
assign('evmzy4', 1, [ 4, 4, 4, 4 ], 1);

my $identifier;
# GET retrieval tests (friendly)
{
    my $retrieve_resp = request($uri . "/friendly/evmzy1");
    my $json = decode_json($retrieve_resp->content);

    ok $retrieve_resp->is_success, "Success returned";
    is $json->{friendly}, 'evmzy1', "Correct friendly returned in payload";
    ok ! $json->{assignments}, 'no assignments included';
    ok ! exists $json->{metadata}, 'no metadata included';

    $retrieve_resp = request($uri . "/friendly/evmzy1?with_metadata=1");
    $json = decode_json($retrieve_resp->content);
    ok $retrieve_resp->is_success, "Retrieved assignmentgroup evmzy1";
    ok exists $json->{metadata}, 'metadata included';
    ok ! $json->{assignments}, 'no assignments included';

    $retrieve_resp = request($uri . "/friendly/evmzy1?with_assignments=1");
    $json = decode_json($retrieve_resp->content);
    ok $retrieve_resp->is_success, "Retrieved assignmentgroup evmzy1";
    ok $json->{assignments}, 'assignments included';
    ok ! exists $json->{metadata}, 'no metadata included';

    $retrieve_resp = request($uri . "/friendly/evmzy1?with_assignments=1&with_metadata=1");
    $json = decode_json($retrieve_resp->content);
    ok $retrieve_resp->is_success, "Retrieved assignmentgroup evmzy1";
    ok $json->{assignments}, 'assignments included';
    ok exists $json->{metadata}, 'metadata included';

    $identifier = $json->{identifier};
}

# store_meta_data test
{
    # Store some information in metadata before test
    $c->model('VennDB::AssignmentGroup')
        ->find_by_identifier($identifier)
        ->update({
            metadata => {
                param1 => 'data1',
                param2 => 'data2',
                custom_data => {
                    param3 => 'data3',
                },
            },
        });

    # Send request
    my $meta_uri = "/api/v1/store_metadata/$identifier";
    my $store_metadata_resp = request(
        POST $meta_uri,
        'Content-Type' => 'application/json',
        'Content' => encode_json({
            hostname => 'izvm2504.devin3.ms.com',
        }),
    );

    my $updated_metadata = $c->model('VennDB::AssignmentGroup')
        ->find_by_identifier($identifier)
        ->metadata;

    # Validate new metadata stored
    is $updated_metadata->{custom_data}->{hostname}, 'izvm2504.devin3.ms.com', "metadata stored";

    # Validate previous metadata have been conserved
    is $updated_metadata->{param1}, 'data1', 'param1 conserved in metadata';
    is $updated_metadata->{param2}, 'data2', 'param2 conserved in metadata';
    is $updated_metadata->{custom_data}->{param3}, 'data3', 'param3 conserved in custom_data';
}
