package Venn::SchemaRole::Result::GeneratorHelpers;

=head1 NAME

package Venn::Schema::ResultSet::GeneratorHelpers

=head1 DESCRIPTION

Moose role to generate Result and ResultSet DBIC classes for P_*, C_*
and NR_* providers.

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

use Moose::Role;

use Data::Dumper;
use Lingua::EN::Inflect::Phrase;

no if $] >= 5.018, warnings => q{experimental::smartmatch};

=head2 __PACKAGE__->subproviders(\%definition)

Creates all Subprovider (P_*) and NamedResource (NR_*) DBIC classes
for a Container (C_*). Registers all classes via
Venn::Schema->register_class() calls.

For %definition format see example in /providers directory.

=cut

sub subproviders {
    my ($self, @params) = @_;

    my $providers = @params == 1 ? $params[0] : {@params};

    for my $name (keys %$providers) {
        my $definition = $providers->{$name};

        my $package = $self->__create_subprovider($name, $definition);

        if (exists $definition->{named_resources}) {
            for my $nr_name (keys %{$definition->{named_resources}}) {
                my $nr_def = $definition->{named_resources}{$nr_name};

                my $nr_package = $self->__create_named_resource(
                    $package, $nr_name, $nr_def);
                $self->__register_class($nr_package);
            }
        }

        # Result's been cooked, register it ;)
        $self->__register_class($package);
    }

    return;
}

=head2 $self->__generate_name_map($class_name, $type)

Creates a map of naming conventions.

    Ex: my $map = $self->__generate_name_map('Cpu_Esx_Cluster', 'subprovider');
        $map = {
            name             => 'Cpu_Esx_Cluster',
            name_capitalized => 'Cpu_Esx_Cluster',
            name_plural      => 'Cpu_Esx_Clusters',
            type             => 'subprovider',
        };

    param $name       : (Str) Name of the object
    param $class_type : (Str) Class type (provider, attribute, etc.) TODO: list these
    return            : (HashRef) Map of naming conventions

=cut

# TODO: use this

sub __generate_name_map { ## no critic [Subroutines::ProhibitUnusedPrivateSubroutines]
    my ($self, $name, $type) = @_;

    my %map = (
        name        => $name,
        type        => $type,
        capitalized => join( '_', map { ucfirst } split(/_/, $name) ),
        plural      => Lingua::EN::Inflect::Phrase::to_PL($name),
    );

    my $pkg_prefix = '';
    given ($type // '') {
        when (/^attribute$/i) {
            $pkg_prefix = 'A_';
        }
        when (/^subprovider$/i) {
            $pkg_prefix = 'P_';
        }
        when (/^named_resource$/i) {
            $pkg_prefix = 'NR_';
        }
        when (/^container$/i) {
            $pkg_prefix = 'C_';
        }
        when (/^join$/) {
            $pkg_prefix = 'J_';
        }
        when (/^misc$/) {
            $pkg_prefix = 'M_';
        }
    }
    $map{package} = $pkg_prefix . $map{capitalized};
    $map{fullpackage} = 'Venn::Schema::Result::' . $map{package};
    $map{rs_fullpackage} = 'Venn::Schema::ResultSet::' . $map{package};

    return \%map;
}

=head2 $self->__create_attribute(\%definition)

Creates an Attribute (A_*) DBIC class and sets all attributes in definition.

Returns $package_name which should be registered via DBIx::Class::Schema.

=cut

sub __create_attribute { ## no critic Subroutines::ProhibitUnusedPrivateSubroutines
    my ($self, $name, $definition) = @_;

    $self->__log("Creating attribute $name");

    my $name_capitalized        = join('_', map {ucfirst} split(/_/, $name));
    my $attr_accessor           = lc $name;
    my $name_plural             = Lingua::EN::Inflect::Phrase::to_PL(lc $name);
    my $package_capitalized     = "A_${name_capitalized}";

    $definition->{type}            = 'attribute';
    $definition->{primary_field} //= keys %{$definition->{columns}[0]};
    $definition->{primary_key}   //= $definition->{primary_field};

    my $attr_package = $self->__create_class($name, $package_capitalized, $definition);
    $self->__register_class($attr_package);

    # create join table (J_) + relationship from A_ to J_

    my $join_package = $self->__create_provider_join_for_attribute($attr_package, $name_capitalized, $name_plural,
        $attr_accessor, $definition);

    $self->__install_custom_relationships($definition->{custom_relationships});

    $self->__register_class($join_package);

    my $join_accessor = "provider_" . lc($name_plural);

    my %has_many_attrs;
    $has_many_attrs{join_type} = 'INNER' if $definition->{explicit_column};

    # A_ relationships
    #$self->log->tracef("Adding has_many for %s from %s => %s", $package_capitalized, $join_accessor, $join_package);
    $attr_package->has_many(
        # provider_environments => Venn::Schema::Result::J_Provider_Environments
        $join_accessor => $join_package,
        # environment
        $definition->{primary_key},
        \%has_many_attrs
    );
    #$self->log->tracef("Adding many_to_many for %s from %s => %s", $package_capitalized, 'providers', $join_accessor);
    $attr_package->many_to_many(
        # providers => provider_environments
        providers => $join_accessor,
        'provider',
    );

    #$self->log->tracef("adding has_many $join_accessor to provider");
    Venn::Schema::Result::Provider->has_many(
        $join_accessor => $join_package,
        'provider_id',
    );

    #Venn::Schema::Result::Provider->many_to_many(
    #    $name_plural => $join_accessor,
    #    $definition->{primary_key},
    #);

    return $attr_package;
}

sub __create_provider_join_for_attribute {
    my ($self, $package, $attrname_capitalized, $attrname_plural, $attr_accessor, $attr_definition) = @_;

    my $name                = "provider_" . $attrname_plural;
    my $package_capitalized = "J_Provider_${attrname_capitalized}";

    my $table = "J_Provider_" . join('_', map {ucfirst} split(/_/, $attrname_plural));

    my %join_definition = (
        type          => 'join',
        table         => uc $table,
        display_name  => "Provider " . $attr_definition->{display_name} // $attrname_capitalized,
        primary_key   => [ 'provider_id', $attr_definition->{primary_key} ],
        primary_field => 'provider_id,' . $attr_definition->{primary_key},
        indices       => [ 'provider_id', $attr_definition->{primary_key} ],
        columns       => [
            {
                provider_id => Venn::Schema::Result::Provider->column_info('provider_id')
            },
            {
                $attr_definition->{primary_key} => $package->column_info($attr_definition->{primary_key}),
            },
        ],
    );

    my $join_package = $self->__create_join($name, $package_capitalized, \%join_definition);

    # J_ relationships
    #$self->log->tracef("Adding belongs_to for %s from %s => %s", $package_capitalized, 'provider', 'Venn::Schema::Result::Provider');
    $join_package->belongs_to(
        provider => 'Venn::Schema::Result::Provider',
        'provider_id',
        {
            on_delete => 'cascade',
            on_update => 'restrict',
        },
    );
    #$self->log->tracef("Adding belongs_to for %s from %s => %s", $package_capitalized, $attr_accessor, $package);
    $join_package->belongs_to(
        $attr_accessor => $package,
        $attr_definition->{primary_key},
        {
            on_delete => 'restrict',
            on_update => 'restrict',
        },
    );

    return $join_package;
}

sub __create_join {
    my ($self, $name, $package_capitalized, $definition) = @_;

    $definition->{type} = 'join';

    return $self->__create_class($name, $package_capitalized, $definition);
}

=head2 $self->__create_container(\%definition)

Creates a Container (C_*) DBIC class and sets all attributes in definition.
It will create all subproviders (P_* and NR_* classes) via setting the
subproviders() attribute.

Returns $package_name which should be registered via DBIx::Class::Schema.

=cut

sub __create_container { ## no critic Subroutines::ProhibitUnusedPrivateSubroutines
    my ($self, $definition) = @_;

    my $name = $definition->{name} // die "Container name not defined";
    my $name_capitalized = join('_', map {ucfirst} split(/_/, $name));
    my $package_capitalized = 'C_'.$name_capitalized;

    $self->__log("Creating container $package_capitalized");

    $definition->{type} = 'container';
    $definition->{primary_field} //= keys %{$definition->{columns}[0]};
    $definition->{container_field} //= '';

    my $package = $self->__create_class($name, $package_capitalized, $definition);

    if ($definition->{containers}) { # recursively create all sub-containers
        for my $key (keys %{$definition->{containers}}) {
            my $container = $package->__create_container($definition->{containers}{$key});

            # register parent-child relations between the containers
            $container->belongs_to(
                $definition->{containers}{$key}{container_name} => $package,
                $definition->{containers}{$key}{container_field},
                {
                    on_delete => 'restrict',
                    on_update => 'restrict'
                },
            );
            $package->has_many(
                $key => $container,
                $definition->{containers}{$key}{container_field},
            );

            $self->__register_class($container);
        }
    }

    return $package;
}

=head2 $self->__create_subprovider($name, \%definition)

Creates a Subprovider (P_*) DBIC class and sets all attributes in definition.

Returns $package_name which should be registered via DBIx::Class::Schema.

=cut

sub __create_subprovider {
    my ($self, $name, $definition) = @_;

    my $self_class = ref($self) || $self;
    my $name_capitalized = $definition->{class} //
      join('_', map {ucfirst} split(/_/, $name));
    my $package_capitalized = 'P_'.$name_capitalized;

    $self->__log("Creating subprovider $package_capitalized");

    $definition->{type} = 'subprovider';
    $definition->{name} //= $package_capitalized;
    $definition->{providertype} //= $name;
    $definition->{primary_field} //=
      $definition->{link_column} // $definition->{columns}[0];
    $definition->{container_field} //= $self_class->primary_field;
    ($definition->{container_class}) = $self_class =~ /^.+::([^:]+)$/
      unless defined $definition->{container_class};

    $self->__save_provider_type($name, $definition);

    my $package = $self->__create_class($name, $package_capitalized, $definition);

    return $package;
}

sub __save_provider_type {
    my ($self, $name, $definition) = @_;

    my $unit = delete $definition->{unit};
    die "unit required for subprovider $name" unless defined $unit;

    my $category = delete $definition->{category};
    die "category required for subprovider $name" unless defined $category;

    Venn::Schema->_build_data->{provider_type}->{$name} = { ## no critic Subroutines::ProtectPrivateSubs
        unit             => $unit,
        category         => $category,
        description      => $definition->{display_name},
        overcommit_ratio => delete $definition->{overcommit_ratio},
    };

    return;
}

=head2 $self->__create_named_resource($parent, $name, \%definition)

Creates a NamedResource (NR_*) DBIC class and sets all attributes in definition.
All relations will be set up pointing to $parent.

Returns $package_name which should be registered via DBIx::Class::Schema.

=cut

sub __create_named_resource {
    my ($self, $parent, $name, $definition) = @_;

    my $self_class = ref($self) || $self;
    my $name_capitalized = $definition->{class} //
      join('_', map {ucfirst} split(/_/, $name));
    my $package_capitalized = 'NR_'.$name_capitalized;

    $self->__log("Creating named resource $package_capitalized");

    $definition->{type} = 'named_resource';
    $definition->{name} //= $package_capitalized;
    $definition->{display_name} //= "Named resources for ".ref($parent);
    $definition->{primary_field} //=
      $definition->{link_column} //
      (ref($definition->{columns}[0]) ? %{$definition->{columns}[0]} : $definition->{columns}[0])[0];

    my $package = $self->__create_class($definition->{name}, $package_capitalized, $definition);

    # P->NR relations
    $parent->has_many(
        'resources' => "Venn::Schema::Result::$package_capitalized",
        'provider_id',
    );
    $parent->has_many(
        $name => "Venn::Schema::Result::$package_capitalized",
        'provider_id',
    );

    return $package;
}

=head2 $self->__create_class($name, $capitalized_name, \%definition)

Creates the DBIC class and applies all attributes.
Called from __create_(container, subprovider, named_resource).

Returns $package_name defined.

=cut

sub __create_class {          ## no critic Subroutines::ProhibitExcessComplexity
    my ($self, $name, $package_capitalized, $definition) = @_;

    my $self_class = $definition->{container_class} || ref($self) || $self;
    $self_class = "Venn::Schema::Result::$self_class" if $self_class !~ /::/;
    my $package = "Venn::Schema::Result::$package_capitalized";

    # setup default and additional roles
    my @roles = $self->__get_result_roles($definition);

    # define Result class
    $self->__new_class($package, 'Venn::SchemaBase::Result', @roles);

    $self->__generate_table_name($package_capitalized, $definition);

    $self->__install_package_attributes($package, $definition, [qw(
        display_name providertype primary_field container_field container_name container_class table
    )]);

    $self->__install_named_resources($package, $definition->{named_resources});

    $self->__install_columns($package, $self_class, $definition);

    $self->__install_indices($package, $package_capitalized, $definition->{indices});

    $self->__install_unique_constraints($package, $name, $package_capitalized, $definition->{unique_constraints});

    $self->__install_subprovider_relationships($package, $name, $definition);

    $self->__install_container_relationship($package, $self_class, $definition->{container_rel},
        $definition->{container_field});

    $self->__install_primary_key($package, $definition->{primary_key});

    $package->subproviders($definition->{subproviders}) if $definition->{subproviders};

    $self->__install_relationships($package, $definition);

    $self->__create_resultset($package, $definition);

    return $package;
}

sub __create_resultset {
    my ($self, $package, $definition) = @_;

    my $resultset_package = ( $package =~ s/Result/ResultSet/r );

    # setup default and additional resultset roles
    my @rs_roles = $self->__get_resultset_roles($definition);

    # create ResultSet, need to be set before register
    $self->__new_class($resultset_package, 'Venn::SchemaBase::ResultSet', @rs_roles);

    # resultset attributes
    for my $attribute (qw(agt_name)) {
        $resultset_package->$attribute($definition->{$attribute}) if defined $definition->{$attribute};
    }
    $package->resultset_class($resultset_package);

    return;
}

# install custom relationships
sub __install_custom_relationships {
    my ($self, $definition) = @_;
    $definition //= {};

    for my $class (keys %$definition) {
        my $data = $definition->{$class};
        $class = "Venn::Schema::Result::${class}" unless $class =~ /::/;
        $self->__install_relationships($class, $data);
    }

    return;
}

# add any remaining additional relations
sub __install_relationships {
    my ($self, $package, $definition) = @_;

    for my $rel_type (qw(has_one has_many might_have belongs_to many_to_many)) {
        for my $rel_name (keys %{$definition->{$rel_type} || {}}) {
            my $def = $definition->{$rel_type}{$rel_name};
            my ($class, $accessor) = ($def->{class}, $def->{accessor});
            $class = "Venn::Schema::Result::$class" if $class && $class !~ /::/;
            my $cond = $def->{condition};
            if ($cond =~ /^\\&(\w+)/) { # handle code-reference
                my $func = $package.'::'.$1;
                $cond = \&$func;
            }

            $self->__log("Inst. rel: %s->%s( %s => %s, %s )", $package, $rel_type, $rel_name, $class // $accessor,
                Data::Dumper->new([ $def->{attributes} ])->Terse(1)->Indent(0)->Dump );
            $package->$rel_type(
                $rel_name => $class // $accessor,
                $cond,
                $def->{attributes},
            );
        }
    }

    return;
}


# set the primary key
sub __install_primary_key {
    my ($self, $package, $pk) = @_;

    $package->set_primary_key( ref $pk ? @$pk : $pk ) if defined $pk;
    return;
}

# explicitly named belongs_to->container
sub __install_container_relationship {
    my ($self, $package, $self_class, $container_rel, $container_field) = @_;

    $package->belongs_to(
        $container_rel => $self_class,
        $container_field,
        { on_update => 'restrict', 'on_delete' => 'restrict' },
    ) if $container_rel && $container_field;
    return;
}

# container has_many/has_one to subprovider
sub __install_subprovider_relationships {
    my ($self, $package, $name, $definition) = @_;

    return unless $definition->{type} eq 'subprovider';

    my $rel_type = ($definition->{relation} && $definition->{relation} eq 'single') ?  'has_one' : 'has_many';
    $self->$rel_type($name => $package, $definition->{container_field});
    return;
}

sub __install_unique_constraints {
    my ($self, $package, $name, $uc_prefix, $unique_constraints) = @_;
    $unique_constraints //= {};

    # add unique key constraints
    for my $key (keys %$unique_constraints) {
        my $index = lc sprintf "uc_%s_%s_idx", $uc_prefix, $key;
        $package->add_unique_constraints( $name => $unique_constraints->{$key} );
    }
    return;
}

sub __install_indices {
    my ($self, $package, $index_prefix, $indices) = @_;
    $indices //= [];

    # add column indices
    for my $col (@$indices) {
        my $index = lc sprintf "%s_%s_idx", $index_prefix, (ref $col ? join('_', @$col) : $col);
        $package->indices({ $index => ref($col) ? $col : [$col] });
    }
    return;
}

# collect + install columns to make around 'add_columns' fire just once
sub __install_columns {
    my ($self, $package, $self_class, $definition) = @_;

    my @columns;

    # add link column, if defined
    if (my $column = $definition->{link_column}) {
        my $info = $self_class->column_info($column) // die "link_column $column was not found in parent $self_class";
        $info->{is_foreign_key} = 1;

        push @columns, $column => $info;
    }

    # add custom columns
    if ($definition->{columns}) {
        for my $col (@{$definition->{columns}}) {
            push @columns, ref($col) ? %$col : $col;
        }
    }

    $package->add_columns(@columns); # columns are finalized here, add them!

    return \@columns;
}

# add config() attributes for named_resources
sub __install_named_resources {
    my ($self, $package, $named_resources) = @_;
    $named_resources //= {};

    foreach my $nr_name (keys %$named_resources) {
        $package->named_resources($nr_name);
        $package->named_resources_resourcename( $named_resources->{$nr_name}{resourcename} );
    }
    return;
}

sub __generate_table_name {
    my ($self, $package_capitalized, $definition) = @_;

    # generate table name if not defined
    $definition->{table} //=
      Lingua::EN::Inflect::Phrase::to_PL($package_capitalized);

    return;
}

# add config() attributes and table
sub __install_package_attributes {
    my ($self, $package, $definition, $attributes) = @_;

    for my $attribute (@$attributes) {
        $package->$attribute($definition->{$attribute})
            if defined $definition->{$attribute} && $package->can($attribute);
    }
    return;
}

=head2 $self->__register_class($package_name)

Registers a previously created DBIC class for Venn::Schema.

=cut

sub __register_class {
    my ($self, $package) = @_;

    my ($register_name) = $package =~ /^.+::([^:]+)$/;

    return Venn::Schema->register_class($register_name, $package);
}

=head2 $self->__new_class($name, $parent, @roles)

Creates a Moose-enhanced Perl object (defines package).

Returns the created package's metaclass.

=cut

sub __new_class {
    my ($self, $name, $parent, @roles) = @_;

    my $metaclass = Moose::Meta::Class->create(
        $name,
        superclasses => [$parent],
        @roles ? (roles => \@roles) : (),
    );

    return $metaclass;
}

=head2 $self->__get_result_roles(\%definition)

Based on the $definition->{type} it returns the default roles for the
DBIC Result class type. It also merges additional roles specified in
$definition->{'+roles'}.

These are found in the implementation's roles.yml file.

Returns @roles array.

=cut

sub __get_result_roles {
    my ($self, $definition) = @_;

    my @roles;
    if ($definition->{roles}) {
        @roles = @{$definition->{roles}};
    }
    else {
        @roles = @{ Venn::Schema::Generator->roles->{Generated}->{Result}->{$definition->{type}} // [] };
    }

    # additional roles
    if ($definition->{'+roles'}) {
        push @roles, ref($definition->{'+roles'}) ? @{$definition->{'+roles'}} : $definition->{'+roles'};
    }

    @roles = map { $_ =~ /::/ ? $_ : "Venn::SchemaRole::Result::$_" } @roles;

    push @roles, 'Venn::Role::Logging';

    return @roles;
}

=head2 $self->__get_resultset_roles(\%definition)

Based on the $definition->{type} it returns the default roles for the
DBIC ResultSet class type. It also merges additional roles specified in
$definition->{'+rs_roles'}.

These are found in the implementation's roles.yml file.

Returns @roles array.

=cut

sub __get_resultset_roles {
    my ($self, $definition) = @_;

    my @roles;
    if ($definition->{rs_roles}) {
        @roles = @{$definition->{rs_roles}};
    }
    else {
        @roles = @{ Venn::Schema::Generator->roles->{Generated}->{ResultSet}->{$definition->{type}} // [] };
    }

    # additional roles
    if ($definition->{'+rs_roles'}) {
        push @roles,
          ref($definition->{'+rs_roles'}) ? @{$definition->{'+rs_roles'}} :
          $definition->{'+rs_roles'};
    }

    @roles = map { $_=~ /::/ ? $_ : "Venn::SchemaRole::ResultSet::$_" } @roles;

    return @roles;
}

sub __log {
    my ($self, $msg, @args) = @_;

    return unless $ENV{VENN_DEBUG_GENERATOR};

    $msg = sprintf $msg, @args if @args;
    $self->log->debug("[GEN] " . $msg);

    return;
}

1;
