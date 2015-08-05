package t::bootstrap::Methods;

use v5.14;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../..";
use lib "$FindBin::Bin/../../lib";

use Venn::Dependencies;
use Venn::Schema;
use Data::Dumper;
use Data::UUID;
use Scalar::Util qw( reftype looks_like_number );

use vars qw( @EXPORT_OK %EXPORT_TAGS );

use Exporter 'import';
@EXPORT_OK = qw(
    create_environment
    create_capability
    create_owner
    create_provider_types


    create_racks
    create_hosts
    create_host
    create_host_container

    create_rack
    create_rack_container
    create_filers
    create_filer
    create_filer_container
    create_io_filer_provider
    create_storage_disk_share
    create_clusters
    create_cluster
    create_cluster_container

    create_network
    create_networks
    create_network_container
    create_hostname_provider
    create_memory_cluster_provider
    create_cpu_cluster_provider
    active_provider_attrs
    create_capability
    create_provider_state

    create_webpools
    create_webpool
    assign_hostport
    exclude_hostport

    add_capability_to_provider
    add_capability_to_provider_by_name
    remove_capability_from_provider
    set_provider_state
    create_environment
    add_environment_to_provider
    add_environment_to_provider_by_name
    remove_environment_from_provider
    add_owner_to_provider
    add_owner_to_provider_by_name
    remove_owner_from_provider

    agt

    asgrp
    assign
    assign_hostname_by_name
    assign_by_name
    testschema
    create_all_agts
);

%EXPORT_TAGS = ('all' => \@EXPORT_OK);

######################################################################################################

## no critic (ProhibitManyArgs,ProhibitCommaSeparatedStatements)

sub testschema {
    state $t_schema;

    return $t_schema if defined $t_schema;

    my $venn_env = $ENV{VENN_ENV} // 'sqlite';

    # use an in memory sqlite db by default for tests
    if (! defined $ENV{VENN_IN_MEMORY} && $venn_env =~ /^sqlite$/i) {
        $ENV{VENN_IN_MEMORY} = 1;
    }

    $t_schema = Venn::Schema->connect(Venn::Schema->generate_connect_info());

    return $t_schema;
}

our $SCHEMA = testschema();
my $ug = Data::UUID->new();

sub create_provider_types {
    my (%types) = @_;

    for my $type (keys %types) {
        my $data = $types{$type};
        $data->{providertype_name} = $type;
        my $ptype = $SCHEMA->resultset('Provider_Type')->create($data);
    }
    return;
}

sub create_racks {
    my ($campus, $building, $num_racks, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner, $networks_per_rack, $hostnames_per_network, $filesystems_per_cluster) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_num = 1;
    $networks_per_rack ||= 0;

    my $i = 0;
    while ($i < $num_racks) {
        my $rack_name = $building . $current_num++;
        create_rack($rack_name, $campus, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner, $networks_per_rack, $hostnames_per_network, $filesystems_per_cluster);
        $i++;
    }
    return;
}

sub create_rack {
    my ($rack_name, $campus, $filers_per_rack, $shares_per_filer, $clusters_per_rack, $envs, $owner, $networks_per_rack, $hostnames_per_network, $filesystems_per_cluster) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_num = 1;

    #warn "Creating rack $rack_name\n";

    my $rack = create_rack_container($rack_name, $campus);

    create_filers($rack_name, $campus, $filers_per_rack, $shares_per_filer, $envs, $owner) if $filers_per_rack;
    create_clusters($rack_name, $clusters_per_rack, $envs, $owner, $filesystems_per_cluster) if $clusters_per_rack;
    create_networks($rack_name, $networks_per_rack, $envs, $owner, $hostnames_per_network) if $networks_per_rack;
    return;
}

sub create_rack_container {
    my ($rack_name, $campus) = @_;

    my %attrs = (
        rack_name    => $rack_name,
        organization => 'ms',
        hub          => 'ny',
        continent    => 'na',
        country      => 'us',
        campus       => $campus,
        city         => 'za',
        building     => substr($rack_name, 0, 2),
    );

    return $SCHEMA->resultset('C_Rack')->create(\%attrs);
}

sub create_filers {
    my ($rack_name, $campus, $filers_per_rack, $shares_per_filer, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_num = 1;

    my $rack_prefix = substr($rack_name, 0, 1);

    my $i = 0;
    while ($i < $filers_per_rack) {
        my $filer_name = sprintf "%sn%s", $campus, $current_num++;
        create_filer($rack_name, $filer_name, $shares_per_filer, $envs, $owner);
        $i++;
    }
    return;
}

sub create_filer {
    my ($rack_name, $filer_name, $shares_per_filer, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_share = 1;

    create_filer_container($rack_name, $filer_name);
    create_io_filer_provider($rack_name, $filer_name, 17000, $envs, $owner);

    my $i = 0;
    while ($i < $shares_per_filer) {
        my $share_name = sprintf "vmdisk%s", $current_share++;
        create_storage_disk_share_provider($rack_name, $filer_name, $share_name, 13574017, $envs, $owner);
        $i++;
    }
    return;
}

sub create_filer_container {
    my ($rack_name, $filer_name) = @_;

    return $SCHEMA->resultset('C_Filer')->create({
        filer_name => $filer_name,
        rack_name  => $rack_name,
    });
}

sub create_host_container {
    my ($rack_name, $hostname) = @_;

    return $SCHEMA->resultset('C_Host')->create({
        hostname => $hostname,
        rack_name  => $rack_name,
    });
}

sub create_io_filer_provider {
    my ($rack_name, $filer_name, $size, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;

    #print STDERR "Creating filer io provider $filer_name: ";

    my $id = $SCHEMA->resultset('P_Io_Filer')
        ->create_with_provider({
            active_provider_attrs(),
            filer_name        => $filer_name,
            providertype_name => 'filerio',
            size              => $size,
        });
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    #warn "$id\n";
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);
    return;
}

sub create_storage_disk_share_provider {
    my ($rack_name, $filer_name, $share_name, $size, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;

    #print STDERR "Creating disk share provider $share_name in $filer_name: ";

    my $id = $SCHEMA->resultset('P_Storage_Disk_Share')
        ->create_with_provider({
            active_provider_attrs(),
            share_name        => $share_name,
            filer_name        => $filer_name,
            providertype_name => 'disk',
            size              => $size,
        });
    #warn "$id\n";
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    #$row->add_environment($environments[int(rand($#environments+1))]);
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);
    return;
}

sub create_clusters {
    my ($rack_name, $clusters_per_rack, $envs, $owner, $filesystems_per_cluster) = @_;
    state $current_num = 1;

    my $rack_prefix = substr($rack_name, 0, 2);

    my $i = 0;
    while ($i < $clusters_per_rack) {
        my $cluster_name = sprintf "%secl%s", $rack_prefix, $current_num++;
        create_cluster($rack_name, $cluster_name, $envs, $owner, $filesystems_per_cluster);
        $i++;
    }
    return;
}
sub create_hosts {
    #    create_hosts($rack_name, $campus, $hosts_per_rack, $filesystems_per_host, $envs, $owner);
    my ($rack_name, $campus, $hosts_per_rack, $filesystems_per_host, $envs, $owner) = @_;
    state $current_num = 1;

    my $rack_prefix = substr($rack_name, 0, 2);

    my $i = 0;
    while ($i < $hosts_per_rack) {
        my $hostname = sprintf "evh%s%s.testdomain.ms.com", $rack_prefix, $current_num++;
        create_host($rack_name, $hostname, $filesystems_per_host,
                    $envs, $owner);
        $i++;
    }
    return;
}

sub create_cluster {
    my ($rack_name, $cluster_name, $envs, $owner, $filesystems_per_cluster) = @_;

    create_cluster_container($rack_name, $cluster_name);
    create_memory_cluster_provider($rack_name, $cluster_name,
        256 * 1024 * 20, $envs, $owner); # 256GB to MB x 20 hosts
    create_cpu_cluster_provider($rack_name, $cluster_name,
        2.2 * 1000 * 8 * 20, $envs, $owner); # 2.2GHz to MHz x 20 hosts

    create_filesystems($cluster_name, $envs, $owner, $filesystems_per_cluster) if $filesystems_per_cluster;
    return;
}

sub create_cluster_container {
    my ($rack_name, $cluster_name) = @_;

    return $SCHEMA->resultset('C_Cluster')->create({
        cluster_name => $cluster_name,
        rack_name    => $rack_name,
    });
}

sub create_memory_cluster_provider {
    my ($rack_name, $cluster_name, $size, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;

    #print STDERR "Creating cluster memory provider $cluster_name: ";

    my $id = $SCHEMA->resultset('P_Memory_Cluster')
        ->create_with_provider({
            active_provider_attrs(),
            cluster_name     => $cluster_name,
            providertype_name => 'ram',
            size              => $size,
        });
    #warn "$id\n";
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    #$row->add_environment($environments[int(rand($#environments+1))]);
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);
    return;
}

sub create_cpu_cluster_provider {
    my ($rack_name, $cluster_name, $size, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;

    #print STDERR "Creating cluster cpu provider $cluster_name: ";

    my $id = $SCHEMA->resultset('P_Cpu_Cluster')
        ->create_with_provider({
            active_provider_attrs(),
            cluster_name      => $cluster_name,
            providertype_name => 'cpu',
            size              => $size,
        });
    #warn "$id\n";
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    #$row->add_environment($environments[int(rand($#environments+1))]);
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);
    return;
}

sub active_provider_attrs {
    my ($attrs) = @_;

    return (
        state_name => 'active',
        available_date => time(),
        overcommit_ratio => undef,
    );
}

sub create_capability {
    my ($capability, $desc, $explicit) = @_;

    my $rs = $SCHEMA->resultset('A_Capability')->create({
        capability       => $capability,
        description      => $desc,
        explicit         => $explicit,
    });

    return $rs;
}

sub _find_provider_by_name {
    my ($provider_type, $primary_field) = @_;

    my %map = %{ $SCHEMA->provider_mapping->{$provider_type} };
    my $rs = $SCHEMA->resultset($map{source});
    my $row = $rs->as_hash->single({ $map{primary_field} => $primary_field });
    die sprintf("No provider found: %s/%s", $map{primary_field}, $primary_field) unless $row;
    return $row;
}

sub add_capability_to_provider_by_name {
    my ($key, $capability, $providertype) = @_;

    my $row = _find_provider_by_name($providertype, $key);
    add_capability_to_provider($row->{provider_id}, $capability);
    return $row->{provider_id};
}

sub add_capability_to_provider {
    my ($provider_id, $capability) = @_;

    my $provider_rs = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
    if ($provider_rs) {
        #return $provider_rs->create_related('capability', { capability => $capability });
        my $cap_rs = $SCHEMA->resultset('A_Capability')->single({ capability => $capability });
        return $provider_rs->add_to_capabilities($cap_rs);
    }
    else {
        die "Cannot add capability: Provider with provider_id => $provider_id doesn't exist\n";
    }
}

sub remove_capability_from_provider {
    my ($provider_id, $capability) = @_;

    my $provider_rs = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
    if ($provider_rs) {
        #return $provider_rs->create_related('capability', { capability => $capability });
        my $cap_rs = $SCHEMA->resultset('A_Capability')->single({ capability => $capability });
        return $provider_rs->remove_from_capabilities($cap_rs);
    }
    else {
        die "Cannot add capability: Provider with provider_id => $provider_id doesn't exist\n";
    }
}

sub set_provider_state {
    my ($provider_id, $state) = @_;

    my $row = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
    $row->update({
        state_name => $state,
    });
    return $row->{'provider_id'};
}

sub create_environment {
    my ($env, $desc) = @_;

    my $rs = $SCHEMA->resultset('A_Environment')->create({
        environment      => $env,
        description      => $desc,
    });

    return $rs;
}
sub add_environment_to_provider_by_name {
    my ($key, $env, $providertype) = @_;
    my $rs = $SCHEMA->resultset('Provider')->fully_populated($key, $providertype);
    die "non-unique assign: ".$rs->count if $rs->count > 1;
    my $row = $rs->as_hash->first;
    my $provider_id = $row->{'provider_id'};
    die "failed to get provider" unless $provider_id;
    add_environment_to_provider($provider_id, $env);
    return $provider_id;
}

sub add_environment_to_provider {
    my ($provider_id, $env_or_envs) = @_;

    my @envs;
    if (ref $env_or_envs eq 'ARRAY') {
        @envs = @$env_or_envs;
    }
    else {
        @envs = $env_or_envs;
    }

    for my $env (@envs) {
        my $provider_rs = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
        if ($provider_rs) {
            #return $provider_rs->create_related('environment', { environment => $env });
            my $rs = $SCHEMA->resultset('A_Environment')->single({ environment => $env });
            return $provider_rs->add_to_environments($rs);
        }
        else {
            die "Cannot add environment: Provider with provider_id => $provider_id doesn't exist\n";
        }
    }
    return;
}

sub remove_environment_from_provider {
    my ($provider_id, $env) = @_;

    my $provider_rs = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
    if ($provider_rs) {
        #return $provider_rs->create_related('environment', { environment => $env });
        my $rs = $SCHEMA->resultset('A_Environment')->single({ environment => $env });
        return $provider_rs->remove_from_environments($rs);
    }
    else {
        die "Cannot add environment: Provider with provider_id => $provider_id doesn't exist\n";
    }
    return;
}

sub create_owner {
    my ($id, $description) = @_;

    my $rs = $SCHEMA->resultset('A_Owner')->create({
        id => $id,
        description => $description // 'test_id',
    });

    return $rs;
}

sub create_provider_state {
    my ($statename, $description) = @_;

    my $rs = $SCHEMA->resultset('Provider_State')->create({
        state_name => $statename,
        description => $description,
    });
    return $rs;
}

sub create_webpools {
    my ($continent, $building, $num_webpools, $hosts_per_webpool, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_num = 1;

    for (0..$num_webpools) {
        my $webpool_name = $continent . $building . $current_num++;
        create_webpool($webpool_name, $hosts_per_webpool, $envs, $owner);
    }

    return;
}

sub create_webpool {
    my ($webpool_name, $hosts_per_webpool, $envs, $owner) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;

    my $webpool = create_webpool_container($webpool_name);

    create_web_hosts($webpool_name, $hosts_per_webpool, $envs, $owner) if $hosts_per_webpool;

    return;
}

sub create_webpool_container {
    my ($webpool_name) = @_;

    my %attrs = (
        webpool_name => $webpool_name,
        continent    => substr($webpool_name, 0, 2),
        building     => substr($webpool_name, 2, 2),
    );

    return $SCHEMA->resultset('C_Webpool')->create(\%attrs);
}

sub create_web_hosts {
    my ($webpool_name, $num_hosts, $envs, $owner ) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_num = 1;

    for (0..$num_hosts) {
        my $hostname = $webpool_name . "_host" . $current_num++;
        create_web_host(
            $webpool_name,
            $hostname,
            substr($webpool_name, 0, 2),
            substr($webpool_name, 2, 2),
            $envs,
            $owner
        );
    }

    return;
}

sub create_web_host {
    my ($webpool_name, $hostname, $continent, $building, $envs, $owner ) = @_;
    $envs //= [ 'dev' ];
    $owner //= 1;
    state $current_num = 1;

    my %attrs = (
        hostname  => $hostname,
        webpool_name => $webpool_name,
        continent => $continent,
        building  => $building,
    );

    $SCHEMA->resultset('C_Host')->create(\%attrs);
    create_memory_host_provider($hostname, 16 * 1024, $envs, $owner); # 16GB to MB
    create_cpu_host_provider($hostname, 3000, $envs, $owner);
    create_ports_provider($hostname, 10, $envs, $owner); #create 10 ports per host

    return;
}

sub create_memory_host_provider {
    my ($hostname, $size, $envs, $owner) = @_;

    $envs //= [ 'dev' ];
    $owner //= 1;

    my $id = $SCHEMA->resultset("P_Memory_Host")
        ->create_with_provider({
            active_provider_attrs(),
            hostname          => $hostname,
            providertype_name => "hostram",
            size              => $size,
        });
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);

    return $row;
}

sub create_cpu_host_provider {
    my ($hostname, $size, $envs, $owner) = @_;

    $envs //= [ 'dev' ];
    $owner //= 1;

    my $id = $SCHEMA->resultset("P_Cpu_Host")
        ->create_with_provider({
            active_provider_attrs(),
            hostname          => $hostname,
            providertype_name => "hostcpu",
            size              => $size,
        });
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);

    return $row;
}

sub create_ports_provider {
    my ($hostname, $num_ports, $envs, $owner) = @_;

    $envs //= [ 'dev' ];
    $owner //= 1;

    my $id = $SCHEMA->resultset("P_Ports_Host")
        ->create_with_provider({
            active_provider_attrs(),
            hostname        => $hostname,
            providertype_name => "hostports",
            size              => 0,
            available_date    => 1,
        });
    my $row = $SCHEMA->resultset('Provider')->with_provider_id($id)->single();
    $row->add_environment(@$envs);
    $row->add_owner(@$owner);

    return $row->id;
}

sub assign_hostport {
    my ($hostname, $pid, $start_port, $num_ports, $committed, $asgrpname) = @_;
    $committed //= 1;
    $asgrpname //= 'webpool';

    my $asgrp = asgrp($asgrpname, $hostname);

    my $port = $SCHEMA->resultset("NR_Hostports")->create({
        'start_port' => $start_port,
        'num_ports' => $num_ports,
        'me.provider_id' => $pid,
    });

    die 'port not created' if !$port;

    return  $SCHEMA->resultset('Assignment')->create({
        provider_id        => $pid,
        assignmentgroup_id => $asgrp->assignmentgroup_id,
        size               => 1,
        committed          => $committed,
        resource_id        => $port->get_column('resource_id'),
    });
}

sub exclude_hostport {
    my ($type, $value, $start, $num) = @_;

    $SCHEMA->resultset('M_Port_Exclusion')->create({
        $type => $value,
        start_port => $start,
        num_ports => $num,
    }) // die 'range not created';

    return;
}

sub add_owner_to_provider_by_name {
    my ($key, $id, $providertype) = @_;
    my $rs = $SCHEMA->resultset('Provider')->fully_populated($key, $providertype);
    die "non-unique assign: ".$rs->count if $rs->count > 1;
    my $row = $rs->as_hash->first;
    my $provider_id = $row->{'provider_id'};
    die "failed to get provider" unless $provider_id;
    add_owner_to_provider($provider_id, $id);

    return $provider_id;
}

sub add_owner_to_provider {
    my ($provider_id, $id) = @_;

    my $provider_rs = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
    if ($provider_rs) {
        #return $provider_rs->create_related('owner', { id => $id });
        my $rs = $SCHEMA->resultset('A_Owner')->single({ id => $id });
        return $provider_rs->add_to_owners($rs);
    }
    else {
        die "Cannot add owner id: Provider with provider_id => $provider_id doesn't exist\n";
    }
    return;
}

sub remove_owner_from_provider {
    my ($provider_id, $id) = @_;

    my $provider_rs = $SCHEMA->resultset('Provider')->single({ provider_id => $provider_id });
    if ($provider_rs) {
        #return $provider_rs->create_related('owner', { id => $id });
        my $rs = $SCHEMA->resultset('A_Owner')->single({ id => $id });
        return $provider_rs->remove_from_owners($rs);
    }
    else {
        die "Cannot add owner id: Provider with provider_id => $provider_id doesn't exist\n";
    }
    return;
}

# create or get assignment group type
sub agt {
    my ($name, $desc, $definition) = @_;
    $name //= 'hosting';
    $desc //= 'hosting agt';

    my $agt = $SCHEMA->resultset('AssignmentGroup_Type')->single({
        assignmentgroup_type_name => $name,
    });
    if ($agt) {
        return $agt;
    }
    else {
        my %definition = (
            # base relationship name
            me             => 'ram',
            # base provider class
            provider_class => 'P_Memory',
            # root container class
            root_container_class => 'C_Rack',
            # root container alias
            root_container_alias => 'rack',
            # list of all relationships
            providers      => {
                ram  => [ 'cluster' ],
                cpu  => [ 'cluster' ],
                disk => [ 'cluster', 'rack', 'filers' ],
                io   => [ 'cluster', 'rack', 'filers' ],
            },
            # where to find location parameters
            location       => {
                rack_name    => ['rack'],
                organization => ['rack'],
                hub          => ['rack'],
                continent    => ['rack'],
                country      => ['rack'],
                campus       => ['rack'],
                city         => ['rack'],
                building     => ['rack'],
            },
            provider_to_location_join => {
                ram  => { 'cluster' => 'rack' },
                cpu  => { 'cluster' => 'rack' },
                disk => { 'filer'   => 'rack' },
                io   => { 'filer'   => 'rack' },
            },
            # join clause for DBIC to get all the above info
            join_clause      => [
                { 'cluster' => { 'rack' => { 'filers' => ['disk', 'io'] } } },
                'cpu',
                'ram',
            ],
            place_format => 'Placed on cluster %s, share %s, filer %s',
            place_args   => [qw( cpu.cluster_name disk.share_name io.filer_name )],
        );
        return $SCHEMA->resultset('AssignmentGroup_Type')->create({
            assignmentgroup_type_name        => $name,
            description => 'Default Hosting AGT',
            #table_name => '',
            definition  => YAML::XS::Dump(\%definition),
        });
    }
    return;
}

# create or get assignment group
sub asgrp {
    my ($agt_name, $vm) = @_;

    my $agt = agt($agt_name);

    my $asgrp = $SCHEMA->resultset('AssignmentGroup')->single({ friendly => $vm });
    if ($asgrp) {
        return $asgrp;
    }
    else {
        return $SCHEMA->resultset('AssignmentGroup')->create({
            assignmentgroup_type_name => $agt->assignmentgroup_type_name,
            identifier => $ug->create_str(),
            friendly => $vm,
        });
    }
    return;
}

sub assign_by_name {
    my ($vm, $key, $size, $committed, $asgrpname, $providertype) = @_;
    my $rs = $SCHEMA->resultset('Provider')->fully_populated($key, $providertype);
    die "non-unique assign: ".$rs->count if $rs->count > 1;
    my $row = $rs->as_hash->first;
    my $provider_id = $row->{'provider_id'};
    return assign($vm, $provider_id, $size, $committed, $asgrpname);
}

sub assign {
    my ($vm, $provider_id, $size, $committed, $asgrpname) = @_;
    $committed //= 1;
    $asgrpname //= 'hosting';

    my $asgrp = asgrp($asgrpname, $vm);
    my $provider = $SCHEMA->resultset('Provider')->with_provider_id($provider_id)->single();
    die "No provider found with id: $provider_id\n" unless $provider;

    my @sizes;
    if (reftype $size && reftype $size eq 'ARRAY') {
        @sizes = @$size;
    }
    else {
        push @sizes, $size;
    }

    my @ids;
    for my $s (@sizes) {
        push @ids, $provider->assign(
            assignmentgroup_id => $asgrp->assignmentgroup_id,
            size               => $s,
        );
    }
    return @ids;
}

sub create_all_agts {
    ## no critic (TestingAndDebugging::ProhibitNoStrict, BuiltinFunctions::RequireBlockGrep)
    no strict 'refs';

    for my $sub (grep /^agt_[a-z0-9_]+$/, keys %{__PACKAGE__.'::'}) {
        &$sub;
    }

    use strict 'refs';
    ## use critic

    return;
}

1;
