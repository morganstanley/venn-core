#!/usr/bin/env perl
#-*-cperl-*-

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Test::Most tests => 8;
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
}

my ($res, $c) = ctx_request();
$c->model('VennDB')->schema($schema);

my @rows = $schema->resultset('Provider_Type')
    ->search(undef, { columns => [qw/ providertype_name /] })
    ->all;
my @all_types = map { $_->providertype_name } @rows;

my $uri = "/api/v1/provider_type";

{   # GET all provider_type
    my $response = request($uri);
    my $json = decode_json($response->content);
    is $response->code, 200, '200 code';
    my @api_types = @$json;
    cmp_set(\@api_types, \@all_types, 'Correct provider types returned');
    is scalar(@api_types), scalar(@all_types), 'Correct number of provider types returned';
}

{   # GET specific provider_type
    my $response = request($uri . "/" . $all_types[0]);
    my $json = decode_json($response->content);
    is $response->code, 200, '200 code';
    is $json->{providertype_name}, $all_types[0], 'Correct provider_type name returned';
}

$uri .= "?data=1";

{   # GET all provider_type with data
    my $response = request($uri);
    my $json = decode_json($response->content);
    is $response->code, 200, '200 code';
    my @api_type_data = @$json;
    my @api_types = map { $_->{providertype_name} } @api_type_data;
    cmp_set(\@api_types, \@all_types, 'Correct provider types returned');
    is scalar(@api_types), scalar(@all_types), 'Correct number of provider types returned';
}

done_testing();
