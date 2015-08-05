package Venn::Schema::Generator;

=head1 NAME

package Venn::Schema::Generator

=head1 DESCRIPTION

Generates Result and ResultSet classes from YAML descriptor files
in providers/ directory

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

use Moose;
BEGIN {
    with qw(
       Venn::SchemaRole::Result::GeneratorHelpers
       Venn::Role::Logging
    );
}
use MooseX::ClassAttribute;
use namespace::autoclean;

use Moose::Util;
use YAML::XS qw(LoadFile);
use List::MoreUtils 'first_index';
use Data::Dumper;

class_has 'roles' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { {} },
    documentation => 'Role mapping',
);

=head2 __PACKAGE__->load_agts_from($dir)

Loads Assignment Group Types (AGTs) from $dir.

    param  $dir : (Str) Directory AGTs are in
    return      : (HashRef) AGTs { $name => $definition, ... }

=cut

sub load_agts_from {
    my ($self, $dir) = @_;

    return unless -d $dir; # skip if missing

    my %agts;

    while (my $file = $dir->next) {
        next unless -f $file && $file =~ /\.yml$/;

        my $yaml = eval { LoadFile($file) };
        if (my $err = $@) {
            die "Unable to load agt definition file $file: $err";
        }

        for my $agt_name (keys %$yaml) {
            my $definition = $yaml->{$agt_name};

            my $description = delete $definition->{description} // '';

            $agts{$agt_name} = {
                assignmentgroup_type_name => $agt_name,
                description => $description,
                definition => $definition,
            };
        }
    }

    return \%agts;
}

=head2 __PACKAGE__->load_roles_from($file)

Loads role definitions from $file

    param $file : (Str) role file

=cut

sub load_roles_from {
    my ($self, $file) = @_;

    return unless -f $file; # skip if missing

    my $roles = eval { LoadFile($file) };
    if (my $err = $@) {
        die "Unable to load roles definition file $file: $err";
    }

    $self->roles($roles);

    return;
}

=head2 __PACKAGE__->apply_roles()

Applies roles to Venn classes.

    ---
    Result:
        Provider:
            - MyRole
        ResultSet:
            MyApp::ResultSet::Provider:
                - MyApp::OtherRole::ResultSet::MyRole

    * applies Venn::SchemaRole::Result::MyRole to Venn::Schema::Result::Provider
    * applies MyApp::OtherRole::ResultSet::MyRole to MyApp::ResultSet::Provider

=cut

sub apply_roles {
    my ($self) = @_;

    # this probably doesn't belong here
    $self->apply_role("Venn::ActionRole::Auth", undef, @{ $self->roles->{Auth} || [] });

    $self->apply_role("Venn::Schema", undef, @{ $self->roles->{Schema} || [] });

    for my $type (qw[ Result ResultSet ]) {
        my %classes = %{ $self->roles->{$type} // {} };
        for my $class (keys %classes) {
            my @roles = @{ $classes{$class} || [] };

            $self->apply_role($class, $type, @roles) if @roles;
        }
    }
    return;
}

=head2 __PACKAGE__->apply_role($class, $default_namespace, @roles)

Applies the roles to the given class.

=cut

sub apply_role {
    my ($self, $class, $type, @roles) = @_;
    $type //= '';

    return unless @roles;

    my $full_class = $class =~ /::/ ? $class : $self->full_package($class, "Venn::Schema::${type}");
    my @full_roles = map { $self->full_package($_, "Venn::SchemaRole::${type}") } @roles;

    $self->log->tracef("Applying roles '%s' to '%s'", join(', ', @full_roles), $full_class);
    return Moose::Util::ensure_all_roles($full_class, @full_roles);
}

=head2 __PACKAGE__->full_package($class, $default_namespace)

Returns the full package name for a class.

=cut

sub full_package {
    my ($self, $class, $default_namespace) = @_;

    return $class if $class =~ /::/; # already full package

    return $default_namespace =~ /::$/ ? "${default_namespace}${class}" : "${default_namespace}::${class}";
}

=head2 __PACKAGE__->load_attributes_from($file)

Loads attribute yml and creates and registers DBIC classes.

=cut

sub load_attributes_from {
    my ($self, $file) = @_;

    return unless -f $file; # skip if missing

    my $attributes = eval { LoadFile($file) };
    if (my $err = $@) {
        die "Unable to load attributes definition file $file: $err";
    }

    for my $attribute (keys %$attributes) {
        my $attr_data = $attributes->{$attribute};
        #$self->log->debug("Attribute: $attribute");
        my $attribute = $self->__create_attribute($attribute, $attr_data);
        $self->__register_class($attribute);
    }

    return;
}

=head2 __PACKAGE__->load_providers_from([$dir])

Loads .yml files from $dir (or the default /providers dir) and
creates, registers DBIC classes using GeneratorHelpers.

=cut

sub load_providers_from {
    my ($self, $dir) = @_;

    return unless -d $dir; # skip if missing

    my (%containers, @order);

    while (my $file = $dir->next) {
        next unless -f $file && $file =~ /\.yml$/;

        my $yaml = eval { LoadFile($file) };
        if (my $err = $@) {
            die "Unable to load provider definition file $file: $err";
        }

        my $name = $file;
        $name =~ s/\.yml$//;
        $name =~ s|^.*/||;
        $containers{$name} = $yaml;
        push @order, $name;
    }

    # no providers is... well, weird
    warn "Venn::Schema: warning, no providers has been loaded!" unless @order;

    # a basic re-ordering with moving all depends_on: definitions to the
    # beginning of @order

    my @depends;
    my $swapped = 1;
 SWAP:
    while ($swapped) {
        $swapped = 0;
        for (my $idx = 0; $idx < @order; ++$idx) {
            my $name = $order[$idx];
            if (exists $containers{$name}{depends_on}) {
                my $depend = $containers{$name}{depends_on};
                unless (exists $containers{$depend}) {
                    die "$name depends_on: $depend, which can't be found!"
                }
                next if grep {$_ eq $depend} @depends;

                splice @order, (first_index {$_ eq $depend} @order), 1; # remove processed
                unshift @order, $depend;
                push @depends, $depend;
                $swapped = 1;
                next SWAP;
            }
        }
    }

    for my $name (@order) {
        my $container = $self->__create_container($containers{$name});
        $self->__register_class($container);
    }

    return;
}

__PACKAGE__->meta->make_immutable;
