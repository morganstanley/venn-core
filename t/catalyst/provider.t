#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 17;
use Catalyst::Test 'Venn';
use Data::Dumper;
use HTTP::Request::Common qw( GET PUT POST DELETE );
use JSON::XS;

$ENV{VENN_TEST} = 1;
$ENV{VENN_IN_MEMORY} //= 1;

use Venn::Schema;

my $schema = testschema();

my $cluster_name = "zzecl$$";

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1 } );
    bootstrap();
    create_rack_container('ny', 'ny');
    create_cluster_container('ny', $cluster_name);
}

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

my $uri = "/api/v1/provider/ram/$cluster_name";

my $db_platform = $schema->storage_type =~ /db2/i ? 'db2' : 'sqlite';

my %data = (
    state_name => 'build',
    providertype_name => 'ram',
    available_date => 1,
    size => 1,
    overcommit_ratio => 1,
);

$data{overcommit_ratio} = '1.00000000000000' if $db_platform eq 'db2';
$data{size} = '1.000000' if $db_platform eq 'db2';

{   # Initial exist tests
    my $response = request($uri);
    warn Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};
    is $response->code, 404, "Cluster doesn't already exist";
}

{   # PUT tests
    my $response = request(
        PUT $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%data),
    );
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    is $response->code, 201, "Created cluster $cluster_name";
}

{   # PUT retrieval tests
    my $response = request($uri);
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    my $json = decode_json($response->content);

    ok $response->is_success, "Retrieved cluster $cluster_name";
    cmp_deeply {
        cluster_name => $cluster_name,
        %data,
    }, subhashof($json), 'Right cluster retrieved';
}

{   # PUT update tests
    $data{state_name} = 'active'; # promote to active

    my $response = request(
        PUT $uri,
        Content_Type => 'application/json',
        Content      => encode_json(\%data),
    );
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    is $response->code, 201, "Updated cluster $cluster_name";
}

{   # PUT retrieval tests
    my $response = request($uri);
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    my $json = decode_json($response->content);

    ok $response->is_success, "Retrieved cluster $cluster_name";
    cmp_deeply {
        cluster_name => $cluster_name,
        %data,
    }, subhashof($json), 'Right cluster retrieved with new state_name';
}

{   # map the QA environment
    my $response = request(
        PUT $uri . '/environment/qa',
        Content_Type => 'application/json',
    );
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    is $response->code, 200, 'qa environment mapped';
}

{   # check that the QA env was mapped via the direct path
    my $response = request($uri . '/environment/qa');
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    ok $response->is_success, 'qa environment mapping verification 1/2';
}

{   # check that the QA env was mapped via the environments path
    my $response = request($uri . '/environment');
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    my $json = decode_json($response->content);

    ok $response->is_success, 'qa environment mapping verification 2/2';
    ok 'qa' ~~ $json, 'qa environment in list';
}

{   # unmap the QA environment
    my $response = request(
        DELETE $uri . '/environment/qa',
        Content_Type => 'application/json',
    );
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    is $response->code, 200, 'qa environment unmapped';
}

{   # check that the QA env was mapped via the direct path
    my $response = request($uri . '/environment/qa');
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    is $response->code, 404, 'qa environment unmapping verification 1/2';
}

{   # check that the QA env was mapped via the environments path
    my $response = request($uri . '/environment');
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    my $json = decode_json($response->content);

    ok $response->is_success, 'qa environment unmapping verification 2/2';
    ok !('qa' ~~ $json), 'qa environment in list';
}

{   # DELETE tests
    my $response = request(
        DELETE $uri,
        'Content-Type' => 'application/json',
    );
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    is $response->code, 200, "Successfully deleted cluster $cluster_name";
}

{   # After DELETE retrieval tests

    my $response = request($uri);
    warn "RESPONSE: " . Dumper($response) if $ENV{VENN_TEST_DUMP_RESPONSE};

    my $json = decode_json($response->content);

    is $response->code, 404, "Can't retrieve deleted cluster $cluster_name";
}

done_testing();
