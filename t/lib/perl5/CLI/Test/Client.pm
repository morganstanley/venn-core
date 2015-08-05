package CLI::Test::Client;

use strict;
use warnings;

use YAML::XS qw(Load);

use base qw(Test::Client);

sub yaml {
    my $self = shift;

    return unless $self->{stdout};

    my $obj = Load($self->{stdout});

    return $obj;
}

1;
