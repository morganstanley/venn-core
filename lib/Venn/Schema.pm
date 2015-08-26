package Venn::Schema;

=head1 NAME

Venn::Schema

=head1 DESCRIPTION

DBIx::Class (DBIC) schema file.

=head1 AUTHOR

Venn Engineering

Josh Arenberg, Norbert Csongradi, Ryan Kupfer, Hai-Long Nguyen

=head1 LICENSE

Copyright 2013,2014,2015 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

use v5.14;
use Moose;
use MooseX::NonMoose;
use MooseX::ClassAttribute;
extends 'DBIx::Class::Schema';
with 'Venn::Role::Logging';
use namespace::autoclean;

use TryCatch;
use Scalar::Util qw( reftype );
use Data::Dumper;
use Lingua::EN::Inflect::Phrase;
use Path::Class qw( file );
use Time::HiRes qw( gettimeofday tv_interval );

use Venn::Schema::Generator;
use Venn::Exception qw(
    API::InvalidAttributeType
    Schema::InvalidVennEnv
);

no if $] >= 5.018, warnings => q{experimental::smartmatch};

# This needs to run ASAP
BEGIN {
    my $venn_env = $ENV{VENN_ENV} // 'sqlite';
    if ($venn_env =~ /^test$/i) {
        my $user = $ENV{VENN_OVERRIDE_USER} || getlogin || getpwuid($<) || "unknown";
        $ENV{VENN_TABLE_PREFIX} //= $user . "_";
    }
}

class_has 'environment' => (
    is      => 'rw',
    isa     => 'Str',
    documentation => 'Venn schema environment',
);

class_has 'sqlite_file' => (
    is      => 'ro',
    isa     => 'Str',
    builder => '_build_sqlite_file',
    lazy    => 1,
    documentation => 'Path to the sqlite file',
);

sub _build_sqlite_file {
    my $user = $ENV{VENN_OVERRIDE_USER} || getlogin || getpwuid($<) || "unknown";

    return $ENV{VENN_IN_MEMORY} ? ':memory:' : sprintf("/var/tmp/venn.%s.sqlite", $user);
}

class_has 'deployed_mapping' => (
    is      => 'rw',
    isa     => 'HashRef[HashRef]',
    lazy    => 1, # leave it as lazy, should run after deployment to get real table state
    builder => '_build_deployed_mapping',
    documentation => 'A mapping of all of the types to their deployed sources',
);

class_has 'provider_mapping' => (
    is      => 'rw',
    isa     => 'HashRef',
    documentation => 'A mapping of provider type (e.g. ram) to metadata',
);

class_has 'container_mapping' => (
    is      => 'rw',
    isa     => 'HashRef',
    documentation => 'A mapping of lower cased container name (e.g. cluster) to metadata',
);

class_has 'attribute_mapping' => (
    is      => 'rw',
    isa     => 'HashRef',
    documentation => 'A mapping of lower cased attr name (e.g. environment) to metadata',
);

class_has '_build_data' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    documentation => 'Temporary map of build data',
);

class_has 'conf_dir' => (
    is      => 'rw',
    isa     => 'Str',
    builder => '_build_conf_dir',
    documentation => 'Directory for providers',
);

sub _build_conf_dir {
    my $env_dir = $ENV{VENN_CONF_DIR};
    if ($env_dir) {
        return Path::Class::Dir->new($env_dir);
    }
    else {
        my $file = file(__FILE__);
        return $file->dir->parent->parent->subdir('etc')->subdir('conf');
    }
}

=head1 METHODS

=head2 before connection()

Calls runtime_init on all result sources before connecting to the database.

=cut

before 'connection' => sub {
    my ($self) = @_;

    for my $sourcename ( $self->sources ) {
        my $class = $self->class($sourcename);
        $class->runtime_init($self) if $class->can('runtime_init');
    }
};

=head2 around connection

Wrap the connection method and set specific per-DB settings.

http://search.cpan.org/~ribasushi/DBIx-Class-0.08250/lib/DBIx/Class/Schema.pm#connect
    B<Overloading>

    B<connect> is a convenience method. It is equivalent to calling $schema->clone->connection(@connectinfo).
    To write your own overloaded version, overload "connection" instead.

=cut

around 'connection' => sub {
    my $orig = shift;
    my $self = shift;
    my ($dsn, $user, $pass, $attrs, @args);
    my ($connect_info) = @_;
    if (defined $connect_info && (reftype $connect_info // '') eq 'HASH') {
        # Catalyst::Model::DBIC::Schema
        $dsn = delete $connect_info->{dsn};
        $user = delete $connect_info->{user} // '';
        $pass = delete $connect_info->{pass} // '';
        $attrs = $connect_info;
    }
    else {
        # Unit tests/normal connect()
        ($dsn, $user, $pass, $attrs, @args) = @_;
    }

    $attrs = {} unless defined $attrs && reftype $attrs eq 'HASH';
    given ($dsn) {
        when (/DB2/i) { # FIXME: MSDB2 Hack
            __PACKAGE__->storage_type( '::DBI::DB2' );
        }
    }
    return $self->$orig($dsn, $user, $pass, $attrs, @args);
};

=head2 around deploy

Before: log deployment, time

After: log, find/create AGTs

=cut

around 'deploy' => sub {
    my $orig = shift;
    my $self = shift;

    $self->log->debug("Deploying database...");

    my $t0 = [ gettimeofday() ];

    my $result = $self->$orig(@_);

    my $elapsed = tv_interval($t0, [ gettimeofday() ]);

    $self->log->debugf("Deployed database in %d seconds", $elapsed);

    $self->create_or_update_agts();
    $self->create_or_update_provider_types();

    return $result;
};

=head2 $self->create_or_update_agts()

Create/update AGTs.

=cut

sub create_or_update_agts {
    my ($self) = @_;
    $self->log->info("Creating/updating AGTs");

    my $agts = __PACKAGE__->load_agts;

    for my $agt_name (keys %$agts) {
        my $definition = $agts->{$agt_name};
        my $agt = $self->resultset('AssignmentGroup_Type')->find($agt_name);
        if ($agt) {
            $self->log->debug("Updating $agt_name");
            $agt->update($definition);
        }
        else {
            $self->log->debug("Creating $agt_name");
            $self->resultset('AssignmentGroup_Type')->create($definition);
        }
    }
    return;
}

=head2 $self->create_or_update_provider_types($update_if_exists)

Create/update Provider Types.

=cut

sub create_or_update_provider_types {
    my ($self) = @_;
    $self->log->info("Creating/updating Provider Types");

    my $provider_types = __PACKAGE__->_build_data->{provider_type};
    die "No provider types defined" unless %$provider_types;

    my $rs = $self->resultset('Provider_Type');
    for my $name (keys %$provider_types) {
        my $definition = $provider_types->{$name};
        $definition->{providertype_name} //= $name;

        my $pt = $rs->find($name);
        if ($pt) {
            $self->log->debug("Updating Provider Type $name");
            $pt->update($definition);
        }
        else {
            $self->log->debug("Creating Provider Type $name");
            $self->resultset('Provider_Type')->create($definition);
        }
    }

    return;
}

=head2 env_connect()

Connects to the correct DB based on $ENV{VENN_ENV}.

See L<generate_connect_info>().

=cut

sub env_connect {
    my ($self) = @_;

    my $connect_info = $self->generate_connect_info();
    $self->log->debug("Connecting to " . Dumper($connect_info));

    return $self->connect($connect_info);
}

=head2 sqlt_deploy_hook($sqlt_schema)

An optional sub which you can declare in your own Schema class that will get passed the
SQL::Translator::Schema object when you deploy the schema via "create_ddl_dir" or "deploy".

Note that sqlt_deploy_hook is called by "deployment_statements", which in turn is called
before "deploy". Therefore the hook can be used only to manipulate the SQL::Translator::Schema
object before it is turned into SQL fed to the database. If you want to execute post-deploy
statements which can not be generated by SQL::Translator, the currently suggested method is to
overload "deploy" and use dbh_do.

See: http://search.cpan.org/~ribasushi/DBIx-Class-0.08250/lib/DBIx/Class/Schema.pm#sqlt_deploy_hook

=cut

sub sqlt_deploy_hook {
    my ( $source, $sqlt_schema ) = @_;

    Venn::Schema::Result::Provider::subprovider_fk_cascade_deploy_hook($source, $sqlt_schema);

    return;
}

=head2 generate_connect_info()

Generates the connect_info hashref

=cut

sub generate_connect_info {
    my ($self) = @_;

    my $venn_env = $ENV{VENN_ENV} // 'sqlite';
    $self->environment($venn_env);

    my $config_data = {};
    if (my $config_file = __PACKAGE__->conf_dir->file('db.yml')) {
        eval {
            $config_data = YAML::XS::LoadFile($config_file);
        };
        $self->log->warn("DB config load error: $@") if $@;
    }

    $config_data->{sqlite} //= {
        dsn           => "dbi:SQLite:dbname=" . Venn::Schema->sqlite_file,
        limit_dialect => 'LimitOffset',
        on_connect_do => [
            'PRAGMA synchronous = OFF',
        ],
        on_connect_call => [
            'use_foreign_keys',
        ],
        AutoCommit    => 1,
        sqlite_see_if_its_a_number => 1,
    };

    return $config_data->{$venn_env} //
      Venn::Exception::Schema::InvalidVennEnv->throw(venn_env => $venn_env);
}

=head2 _build_deployed_mapping()

Builds all currently deployed sources into one map.

=cut

sub _build_deployed_mapping {
    my ($self) = @_;

    my %deployed_mapping;

    for my $type (qw{ provider attribute container }) {
        my $method = sprintf "%s_mapping", $type;

        my $mapping = __PACKAGE__->$method;
        for my $key (keys %$mapping) {
            my $data = $mapping->{$key};
            if ($self->is_source_deployed($data->{source})) {
                $deployed_mapping{$type}{$key} = $data;
            }
            else {
                $self->log->warn("Source: $key either isn't deployed or doesn't match the schema definition");
            }
        }
    }

    return $self->deployed_mapping(\%deployed_mapping);
}

=head2 _build_mappings()

Helper function to call all _build*_mapping() functions, after dynamic DBIC
classes have been built.
Do not convert it to lazy builder, it might introduce race conditions.

=cut

sub _build_mappings {
    my ($self) = @_;

    $self->_build_provider_mapping();
    $self->_build_container_mapping();
    $self->_build_attribute_mapping();

    return;
}

=head2 is_source_deployed($source)

Determines if a source has been deployed.

    param $source : (Str) Name of the source
    return        : (Bool) True if table exists

=cut

sub is_source_deployed {
    my ($self, $source) = @_;

    try {
        $self->resultset($source)->search(undef, { where => \q( 1 = 0 ), rows => 1 })->single;
        $self->log->trace("is_source_deployed($source): yes");
        return 1;
    }
    catch ($err) {
        $self->log->debug($err);
        $self->log->trace("is_source_deployed($source): no");
        return 0;
    }
}

=head2 _build_provider_mapping()

Builds a mapping of provider type (memory) to class name (P_Memory_Cluster)
by looking for all P_* result sources and accessing their providertype names through
the Moose class attribute 'providertype'.

=cut

sub _build_provider_mapping {
    my ($self) = @_;

    my %map;

    my @providers = grep { /^P_/ } $self->sources;
    for my $provider (@providers) {
        my $provider_package = "Venn::Schema::Result::" . $provider;
        if ($provider_package->can('providertype')) {
            $map{$provider_package->providertype} = {
                source          => $provider,
                plural          => Lingua::EN::Inflect::Phrase::to_PL($provider_package->providertype),
                primary_field   => $provider_package->primary_field,
                container_field => $provider_package->container_field,
                display_name    => $provider_package->display_name,
                relationships   => [$provider_package->relationships],
            };
        }
        else {
            Venn::Exception::Schema::MissingRequiredData->throw({
                source  => $provider,
                missing => 'providertype class attribute',
            });
        }
    }

    return $self->provider_mapping(\%map);
}

=head2 attribute_info($attribute)

Returns info an an attribute from the attribute_mapping (see docs for that for details).
Throws an exception if not found.

    param $attribute : (Str) Name of the attribute
    return           : (HashRef) Attribute info
    throws           : (Venn::Exception::API::InvalidAttributeType) Invalid attribute type

=cut

sub attribute_info {
    my ($self, $attribute) = @_;

    if (! defined $self->attribute_mapping->{$attribute}) {
        Venn::Exception::API::InvalidAttributeType->throw({ attributetype => $attribute });
    }

    return $self->attribute_mapping->{$attribute};
}

=head2 _build_container_mapping()

Builds a mapping of lower cased container name (environment) to metadata by looking for all A_* result sources.

=cut

sub _build_container_mapping {
    my ($self) = @_;

    my %map;

    my @containers = grep { /^C_/ } $self->sources;
    for my $container (@containers) {
        my $lc_name = lc $container;
        $lc_name    =~ s/^c_//;

        my $container_package = "Venn::Schema::Result::" . $container;

        $map{$lc_name} = {
            source          => $container,
            plural          => Lingua::EN::Inflect::Phrase::to_PL($lc_name),
            primary_field   => $container_package->primary_field,
            container_field => $container_package->container_field,
            display_name    => $container_package->display_name,
        };
    }

    return $self->container_mapping(\%map);
}

=head2 _build_attribute_mapping()

Builds a mapping of lower cased attribute name (environment) to metadata by looking for all A_* result sources.

=cut

sub _build_attribute_mapping {
    my ($self) = @_;

    my %map;

    my @attributes = grep { /^A_/ } $self->sources;
    for my $attribute (@attributes) {
        my $lc_name = lc $attribute;
        $lc_name    =~ s/^a_//;

        my $attribute_package = "Venn::Schema::Result::" . $attribute;

        $map{$lc_name} = {
            source        => $attribute,
            plural        => Lingua::EN::Inflect::Phrase::to_PL($lc_name),
            primary_field => $attribute_package->primary_field,
            display_name  => $attribute_package->display_name,
        };
    }

    return $self->attribute_mapping(\%map);
}

sub load_providers {
    my ($self, $dir) = @_;

    unless ($dir && -d $dir) {
        $dir = __PACKAGE__->conf_dir->subdir('providers');
    }
    unless (-d $dir) {
        die __PACKAGE__." startup failed, no 'providers' directory found at $dir";
    }
    Venn::Schema::Generator->load_providers_from($dir);
    return;
}

sub load_attributes {
    my ($self, $file) = @_;

    my $attribute_file = __PACKAGE__->conf_dir->file('attributes.yml');
    Venn::Schema::Generator->load_attributes_from($attribute_file) if -f $attribute_file;
    return;
}

sub load_roles {
    my ($self) = @_;

    my $role_file = __PACKAGE__->conf_dir->file('roles.yml');
    Venn::Schema::Generator->load_roles_from($role_file) if -f $role_file;
    return;
}

sub apply_roles {
    my ($self) = @_;

    Venn::Schema::Generator->apply_roles();
    return;
}

sub load_agts {
    my ($self, $dir) = @_;

    unless ($dir && -d $dir) {
        $dir = __PACKAGE__->conf_dir->subdir('agt');
    }
    unless (-d $dir) {
        die __PACKAGE__." startup failed, no 'agt' directory found at $dir";
    }
    return Venn::Schema::Generator->load_agts_from($dir);
}

__PACKAGE__->load_roles;
__PACKAGE__->load_providers;
__PACKAGE__->load_attributes;
__PACKAGE__->load_namespaces;
__PACKAGE__->apply_roles;
__PACKAGE__->_build_mappings;


#__PACKAGE__->meta->make_immutable(inline_constructor => 0);

1;
