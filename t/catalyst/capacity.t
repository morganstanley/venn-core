#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 17; die_on_fail;
use Catalyst::Test 'Venn';
use Data::Dumper;
use HTTP::Request::Common qw( GET PUT POST DELETE );
use JSON::XS;

$ENV{VENN_TEST} = 1;
$ENV{VENN_IN_MEMORY} //= 1;

my $schema = testschema();

# Time before providers are created
my $t0 = time() - 1;

unless ($ENV{VENN_TEST_NODEPLOY}) {
    $schema->deploy( { add_drop_table => 1 } );
    bootstrap();
    create_racks('ny', 'zy', 1, 2, 2, 2, [ 'qa' ], [ 1 ]); # Provider ID's 1-10
    create_racks('ny', 'zy', 1, 1, 1, 1, [ 'prod' ], [ 1 ]); # PRovider ID's 11-14

    # Add capabilities to providers
    create_capability('explicit_a', '', 1);
    create_capability('explicit_b', '', 1);
    create_capability('non_explicit_a', '', 0);
    for (my $i = 1; $i <= 10; $i++) {
        add_capability_to_provider($i, 'explicit_a');
        add_capability_to_provider($i, 'explicit_b');
        add_capability_to_provider($i, 'non_explicit_a');
    }

    # Set build state for providers 11-14
    for (my $i = 11; $i <= 14; $i++) {
        set_provider_state($i, 'build');
    }
}

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

my $capacity_uri = "/api/v1/capacity/hosting";

# Placement options
my $data = {
    resources => {
        ram => 4,
        cpu => 2000,
        filerio => 20,
        disk => 60,
    },
    attributes => {
        environment => 'qa',
        capability => {
            ram => [ 'explicit_a', 'explicit_b' ],
            cpu => [ 'explicit_a', 'explicit_b' ],
            disk => [ 'explicit_a', 'explicit_b' ],
            filerio => [ 'explicit_a', 'explicit_b' ],
        },
        owner => [1],
    },
    location => {
        campus => 'ny',
        continent => 'na',
        building => 'zy',
    },
};

# Options for resize capacity (triple of placement above)
my $resize_cap_data = {
    resources => {
        ram => 12,
        cpu => 6000,
        filerio => 60,
        disk => 180,
    },
};

# Request for capacity with specified placement options
{
    my $capacity_resp = request(
        POST $capacity_uri,
        Content_Type => 'application/json',
        Content => encode_json($data),
    );
    is $capacity_resp->code, 200, 'Correct return code';
    my $json = decode_json($capacity_resp->content);
    is $json->{capacity}, 352, 'Correct capacity count';
}

# Place a guest
my $t1 = time();
sleep 1;
my $identifier;
{
    my $place_uri = "/api/v1/place/hosting/biggest_outlier";
    my $place_resp = request(
        POST $place_uri,
        Content_Type => 'application/json',
        Content      => encode_json($data),
    );

    my $result = decode_json($place_resp->content);
    $identifier = $result->{assignmentgroup}->{identifier};
}

# Request for capacity again (total should be -1)
{
    my $capacity_resp = request(
        POST $capacity_uri,
        Content_Type => 'application/json',
        Content => encode_json($data),
    );
    my $json = decode_json($capacity_resp->content);
    is $json->{capacity}, 351, 'Correct capacity count';
}

# Request for capacity at t1 (full)
{
    $data->{as_of_date} = $t1;
    my $capacity_resp = request(
        POST $capacity_uri,
        Content_Type => 'application/json',
        Content => encode_json($data),
    );
    my $json = decode_json($capacity_resp->content);
    is $json->{capacity}, 352, 'Correct capacity count at t1';
    is $json->{as_of_date}, $t1, 'Correct as_of_date at t1';

    delete $data->{as_of_date};
}

# Request for capacity at t0 (before providers were created)
{
    $data->{as_of_date} = $t0;
    $data->{provider_as_of_date} = $t0;
    my $capacity_resp = request(
        POST $capacity_uri,
        Content_Type => 'application/json',
        Content => encode_json($data),
    );
    my $json = decode_json($capacity_resp->content);
    is $json->{capacity}, 0, 'No capacity at t0';

    delete $data->{as_of_date};
    delete $data->{provider_as_of_date};
}

# Multiple capacity requests at t0, t1 and now (before providers were created)
{
    my $t2 = time();
    $data->{as_of_date} = [ $t0, $t1, $t2 ];
    my $capacity_resp = request(
        POST $capacity_uri,
        Content_Type => 'application/json',
        Content => encode_json($data),
    );

    my $json = decode_json($capacity_resp->content);
    my $cap_t0 = $json->[0];
    my $cap_t1 = $json->[1];
    my $cap_now = $json->[2];

    is $cap_t0->{capacity}, 352, 'Correct capacity at t0';
    is $cap_t0->{as_of_date}, $t0, 'Correct date for t0';
    is $cap_t1->{capacity}, 352, 'Correct capacity count at t1';
    is $cap_t1->{as_of_date}, $t1, 'Correct date for t1';
    is $cap_now->{capacity}, 351, 'Correct capacity count at present time';
    is $cap_now->{as_of_date}, $t2, 'Correct date for present time t2';

    delete $data->{as_of_date};
}

# Resize capacity
{
    my $resize_cap_uri = "/api/v1/resize_capacity/hosting/$identifier";
    my $resize_cap_resp = request(
        POST $resize_cap_uri,
        Content_Type => 'application/json',
        Content      => encode_json($resize_cap_data),
    );

    my $result = decode_json($resize_cap_resp->content);
    ok $resize_cap_resp->is_success, 'Enough capacity for resize capacity request';

    # Negative test
    $resize_cap_data->{resources}->{ram} = 10000000;
    $resize_cap_resp = request(
        POST $resize_cap_uri,
        Content_Type => 'application/json',
        Content      => encode_json($resize_cap_data),

    );
    $result = decode_json($resize_cap_resp->content);
    ok !$resize_cap_resp->is_success, 'No capacity for resize capacity request';
}

# Provider state capacity
{
    my $resp;
    my $result;
    my $placement = {
        resources => {
            ram => 4,
            cpu => 2000,
            filerio => 20,
            disk => 60,
        },
        provider_state => 'build',
        attributes => {
            environment => 'prod',
            capability => {
            },
            owner => [1],
        },
        location => {
            campus => 'ny',
            continent => 'na',
            building => 'zy',
        },
    };

    # With build state
    $resp = request(
        POST $capacity_uri,
        Content_Type    => 'application/json',
        Content         => encode_json($placement),
    );
    $result = decode_json($resp->content);
    is $result->{capacity}, 176, 'Correct capacity count for build state';

    # Active state
    $placement->{provider_state} = 'active';
    $resp = request(
        POST $capacity_uri,
        Content_Type    => 'application/json',
        Content         => encode_json($placement),
    );
    $result = decode_json($resp->content);
    is $result->{capacity}, 0, 'No available capacity';

    # Default state is active
    delete $placement->{provider_state};
    $resp = request(
        POST $capacity_uri,
        Content_Type    => 'application/json',
        Content         => encode_json($placement),
    );
    $result = decode_json($resp->content);
    is $result->{capacity}, 0, 'No available capacity';
}

done_testing();
