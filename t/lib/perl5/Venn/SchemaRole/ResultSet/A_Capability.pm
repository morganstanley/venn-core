package Venn::SchemaRole::ResultSet::A_Capability;

use v5.14;
use warnings;

use Moose::Role;

sub jcf_placement {
    my ($self, $engine, $resname, $me) = @_;

    # no capability specified for $resname
    return unless exists $engine->request->attributes->{capability}->{$resname};

    # no capability checking for forced manual placements
    return if exists $engine->request->{manual_placement}->{$resname} && $engine->request->{force_placement};

    my $res_capabilities = $engine->request->attributes->{capability}->{$resname};

    my %capabilities_placement;

    if ( defined $res_capabilities && @$res_capabilities ) {
        # if the incoming placement request specifies capabilities for a
        # specific resource, add them to the query
        # include only providers with the listed capabilities
        # but exclude any of those providers with explicit capabilities not listed in the capabilities hash

        my $subqryrs = $self
            ->search({
                'me.explicit' => 1,
                'me.capability' => { -not_in => $res_capabilities },
            }, {
                select => 'provider_capabilities.provider_id',
                join   => 'provider_capabilities',
            });

        my $having_clause = sprintf("COUNT(DISTINCT me.capability) >= %s", scalar(@$res_capabilities));

        my $nonexpsubq = $self
            ->search({
                'me.capability' => { -in => $res_capabilities },
            }, {
                group_by => 'provider_capabilities.provider_id',
                having   => \$having_clause,
                join     => 'provider_capabilities'
            });

        $capabilities_placement{"${me}.provider_id"} = {
            not_in => $subqryrs->get_column('provider_capabilities.provider_id')->as_query,
            in     => $nonexpsubq->get_column('provider_capabilities.provider_id')->as_query,
        };
    }
    else {
        # include any providers with no capabilities or with non-explicit capabilities
        # exclude any providers with explicit capabilities
        my $subqryrs = $self
            ->search({
                'me.explicit' => 1,
            }, {
                select => 'provider_capabilities.provider_id',
                join   => 'provider_capabilities'
            });
        $capabilities_placement{"${me}.provider_id"} = [
            { not_in => $subqryrs->get_column('provider_capabilities.provider_id')->as_query },
            undef
        ];
    }

    return \%capabilities_placement;
}

1;
