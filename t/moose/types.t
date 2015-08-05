#!/usr/bin/env perl
package t::moose::types;

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../..";

use t::bootstrap::Bootstrap 'bootstrap';
use t::bootstrap::Methods qw( :all );

use Venn::Exception qw(
    API::BadPlacementResult
);

use Test::Most tests => 10;

## no critic (ProhibitMultiplePackages)

package TypesTest;
    use Moose;
    use Venn::Types qw(:all);

    has 'venn_exception' => (
        is => 'rw',
        isa => VennException,
    );

    has 'non_neg' => (
        is => 'rw',
        isa => NonNegativeNum,
    );

    has 'not_empty_str' => (
        is => 'rw',
        isa => NotEmptyStr,
    );

    has 'placement_result_state' => (
        is => 'rw',
        isa => PlacementResultState,
    );

    no Moose;

package t::moose::types;

my $tt;

lives_ok { $tt = TypesTest->new(non_neg => 1) } '(NonNegativeNum) positive number succeeds';
dies_ok { $tt = TypesTest->new(non_neg => -1) } '(NonNegativeNum) negative number fails';
dies_ok { $tt = TypesTest->new(non_neg => "str") } '(NonNegativeNum) string fails';

lives_ok { $tt = TypesTest->new(venn_exception => Venn::Exception->new(message => 'msg')) } '(VennException) non specific exception';
lives_ok { $tt = TypesTest->new(venn_exception => Venn::Exception::API::BadPlacementResult->new(result => { stuff => 'things' })) } '(VennException) subtype exception';
dies_ok { $tt = TypesTest->new(venn_exception => 1) } '(VennException) int';
dies_ok { $tt = TypesTest->new(venn_exception => "str") } '(VennException) string';

lives_ok { $tt = TypesTest->new(not_empty_str => 'string here') } '(NotEmptyStr) Not empty string succeeds';
dies_ok { $tt = TypesTest->new(not_empty_str => '') } '(NotEmptyStr) Empty string fails';
dies_ok { $tt = TypesTest->new(not_empty_str => undef) } '(NotEmptyStr) Undefined fails';

done_testing();

1;
