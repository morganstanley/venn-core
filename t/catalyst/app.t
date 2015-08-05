#!/usr/bin/env perl

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../..";
use lib "$FindBin::Bin/../../lib";

use Venn::Dependencies;
use t::Dependencies;

use Test::More;

use Catalyst::Test 'Venn';

ok( request('/')->is_redirect, 'GET / redirects properly' );

done_testing();
