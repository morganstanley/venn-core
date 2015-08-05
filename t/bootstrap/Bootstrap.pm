package t::bootstrap::Bootstrap;

use v5.14;
use warnings;

BEGIN {
    use File::Spec;
    my ($volume, $dir, $file) = File::Spec->splitpath(__FILE__);

    $ENV{VENN_ENV} //= 'sqlite';
    $ENV{VENN_TEST} = 1;
    $ENV{VENN_IN_MEMORY} //= 1;

    $ENV{VENN_CONF_DIR} = "$dir/../conf";

    # don't "use lib", that's evaluated before $dir
    push @INC, "$dir/../..", "$dir/../../lib", "$dir/../lib/perl5";
}

use Venn::Dependencies;
use t::Dependencies;
use Venn::Schema;

use t::bootstrap::Methods qw( :all );

use vars qw( @EXPORT_OK %EXPORT_TAGS );

use Exporter 'import';
@EXPORT_OK = qw( bootstrap );
%EXPORT_TAGS = ('all' => \@EXPORT_OK);

sub bootstrap {
    create_environment($_, "$_ environment") for qw( prod qa dev );
    create_capability($_, "$_ capability", 0) for qw( salt pepper );
    create_owner($_) for (0..99);
    create_provider_state($_, lcfirst $_) for qw(active build decommissioned disabled pending);

    return;
}
