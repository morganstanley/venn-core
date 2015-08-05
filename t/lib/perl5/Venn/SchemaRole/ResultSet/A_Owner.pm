package Venn::SchemaRole::ResultSet::A_Owner;

use v5.14;
use warnings;

use Moose::Role;

sub jcf_placement {
    my ($self, $engine, $resname, $me) = @_;

    return unless exists $engine->request->attributes->{owner}->{$resname};

    return if exists $engine->request->{manual_placement}->{$resname} && $engine->request->{force_placement};

    return {
        "${resname}_provider_owners.id" => $engine->request->attributes->{owner}->{$resname},
    };
}

1;
