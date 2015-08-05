package Venn::SchemaRole::ResultSet::A_Environment;

use v5.14;
use warnings;

use Moose::Role;

sub jcf_placement {
    my ($self, $engine, $resname, $me) = @_;

    return unless exists $engine->request->attributes->{environment}->{$resname};

    return {
        "${resname}_provider_environments.environment" => $engine->request->attributes->{environment}->{$resname},
    };
}

1;
