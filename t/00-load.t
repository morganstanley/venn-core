#!perl

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More tests => 2;

BEGIN {
	use_ok( 'Venn::Dependencies' );
	use_ok( 'Venn' );
}

diag( "Testing Venn $Venn::VERSION, Perl $], $^X" );
