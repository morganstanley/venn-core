#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 7;
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

    #my ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner) = @_;
    create_racks('ny', 'ny', 2, 2, 2, 2, [ 'dev' ], [ 1 ]);
}

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

my $uri = "/api/v1/assignment";

my $assignment_id_1 = assign('evmzy1', 1, 8, 1);
my $assignment_id_2 = assign('evmzy1', 1, 8, 1);

{   # GET retrieval tests
    my $retrieve_resp = request($uri . "/" . $assignment_id_1);
    my $json = decode_json($retrieve_resp->content);

    ok $retrieve_resp->is_success, "Retrieved assignment $assignment_id_1";
    is $json->{assignment_id}, $assignment_id_1, "Correct assignment_id returned in payload";
    is $json->{provider_id}, 1, "Correct provider_id returned in payload";
    cmp_ok $json->{size}, '==', 8, "Correct assignment size";
    is $json->{committed}, 0, "Assignment is not committed";
}

{   # PUT commit tests
    my $insert_resp = request(
        POST $uri . "/${assignment_id_1}/commit",
        Content_Type => 'application/json',
        #Content      => encode_json(\%data),
    );
    my $json = decode_json($insert_resp->content);

    is $insert_resp->code, 200, "Committed assignment";
    ok $json->{committed} > 0, 'Commit confirmed';
}

done_testing();
