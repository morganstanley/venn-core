package Venn::SchemaRole::Result::Provider;

=head1 NAME

Venn::SchemaRole::Result::Provider

=head1 DESCRIPTION

Provider result methods.

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
use MooseX::ClassAttribute;

use Lingua::EN::Inflect::Phrase;

no if $] >= 5.018, warnings => q{experimental::smartmatch};

class_has '__runtime_init_called' => (
    is  => 'rw',
    isa => 'Bool',
    documentation => 'Has runtime_init been called?',
);

=head1 METHODS

=head2 runtime_init

Sets up dynamic joins for all attributes (e.g. environments, capabilities and ownerids) for each subprovider.

    param $schema : (DBIC Schema) Schema object

=cut

sub runtime_init {
    my ($class, $schema) = @_;

    return if $class->__runtime_init_called;

    $class->__runtime_init_called(1);

    my $attr_rel_map = $class->_attribute_relation_map();

    my $provider_src = $schema->source('Provider');

    for my $sourcename ( $schema->sources ) {
        my $classname = $schema->class($sourcename);

        given ($sourcename // '') {
            when (/^P_/) {
                my $providertype = $classname->providertype;

                $provider_src->add_relationship(
                    $providertype, $classname,
                    { 'foreign.provider_id' => 'self.provider_id' }, { join_type => 'LEFT', accessor => 'multi', },
                    { on_delete => 'cascade', cascade_delete => 1 },
                );

                for my $attr (keys %$attr_rel_map) {
                    my $join_table = $attr_rel_map->{$attr};
                    my $provider_relationship = sprintf "%s_provider_%s", $providertype, $attr;
                    my $join_table_package = sprintf "Venn::Schema::Result::%s", $join_table;
                    #$class->log->debugf("Adding relationship %s => %s to Provider", $provider_relationship, $join_table_package);
                    $provider_src->add_relationship(
                        # filerio_provider_environments, Venn::Schema::Result::J_Provider_Environment
                        $provider_relationship, $join_table_package,
                        { 'foreign.provider_id' => 'self.provider_id' }, { join_type => 'LEFT OUTER', accessor => 'multi', },
                    );
                    # TODO: not working yet - need to map P_Io_Filer environments
                    #$schema->source($sourcename)->add_relationship(
                    #    $attr, $join_table_package,
                    #    { 'foreign.provider_id' => 'self.provider_id' }, { join_type => 'LEFT OUTER', accessor => 'multi', },
                    #);
                }
            }
        }

        # check for ResultSet class - missing that leads to cryptic errors
        # generate a default one when it's not present
        # an existing file in Schema/ResultSet dir will always take precedence!
        if (ref($schema->resultset($classname)) eq 'DBIx::Class::ResultSet') {
            my ($shortname) = $classname =~ /^.+::(.+)$/;
            my $resultset_name = "Venn::Schema::ResultSet::$shortname";
            my $result_name    = "Venn::Schema::Result::$shortname";

            Moose::Meta::Class->create(
                $resultset_name,
                superclasses => [qw/Venn::SchemaBase::ResultSet/],
            );
            $result_name->resultset_class($resultset_name);
            Venn::Schema->register_class($shortname, $result_name);
        }
    }

    my %attribute_map = %{ Venn::Schema->attribute_mapping };
    for my $attr (keys %attribute_map) {
        my %info = %{ $attribute_map{$attr} };
        Venn::Schema::Result::Provider->meta->add_method(
            "add_${attr}" => sub {
                my ($self, @attrs) = @_;
                my @rows;
                for my $a (@attrs) {
                    my $row = $self->result_source->schema->resultset($info{source})->find($a)
                        || die sprintf("%s %s not found", $info{display_name}, $a);
                    push @rows, $row;
                }

                my $method = "add_to_" . $info{plural};
                die "Cannot add attribute (accessor $method not hooked up)" unless $self->can($method);
                for my $row (@rows) {
                    $self->$method($row);
                }

                return $self;
            }
        );
        Venn::Schema::Result::Provider->meta->add_method(
            "add_" . $info{plural} => sub {
                my $method = "add_${attr}";
                goto &$method;
            }
        );

        $class->many_to_many(
            $info{plural} => 'provider_' . $info{plural},
            $attr,
        );
    }

    Venn::Schema::Result::Provider->meta->make_immutable(inline_constructor => 0);

    return;
};

=head2 _attribute_relation_map

Returns an attribute relationship map to set up dbic relationships.

    return : (HashRef) attribute => join table hashref

    { # IN
        environment => 'A_Environment',
        owner       => 'A_Owner',
        capability  => 'A_Capability',
    };
    { # OUT
        environments => 'J_Provider_Environment',
        owner        => 'J_Provider_Owner',
        capabilities => 'J_Provider_Capability',
    };

=cut

sub _attribute_relation_map {
    my ($self) = @_;

    my %new_map;

    my %attr_map = %{Venn::Schema->attribute_mapping};
    for my $attr (keys %attr_map) {
        my $attrinfo = $attr_map{$attr};
        my $join_table = $attrinfo->{source};
        $join_table =~ s/^A_/J_Provider_/;
        $new_map{$attrinfo->{plural}} = $join_table;
    }
    return \%new_map;
}

=head2 subprovider_fk_cascade_deploy_hook

Shameless hack to get around the fact that dbic looks at the provider class relationships
for hints on the cascade delete settings for the subproviders. Since we create those
relationships in runtime, it causes a problem at deploy time. This is a way around,
based on the table and constraint names.

This function is called by dbic deploy from Venn::Schema::sqlt_deploy_hook

=cut

sub subprovider_fk_cascade_deploy_hook {
    my ( $source, $sqlt_schema ) = @_;

    my $prefix = Venn::SchemaBase::Result->_table_prefix; ## no critic (ProtectPrivateSubs)

    foreach my $table ( $sqlt_schema->get_tables ) {
        my $str = $prefix . 'P_'; #subprovider tables all start with P_
        next unless $table->name =~ /^$str/;
        foreach my $constraint ( $table->get_constraints ) {
            next unless ( $constraint->type eq 'FOREIGN KEY' );
            # we only want the fk constraints on the provider table
            next unless ( $constraint->name =~ /provider_id$/ );
            $constraint->on_delete('CASCADE');
        }
    }
    return;
}


=head2 assignment_sum()

Returns the sum of all assignments for this provider.

    return : (Num) Sum of assignments

=cut

# TODO: committed option ?
sub assignment_sum {
    my ($self) = @_;

    return $self->assignments->get_column('size')->sum();
}

=head2 overcommitted($with_extra)

Check if this provider has been overcommitted (optionally including extra usage).

    param $with_extra : (Int) Extra usage (size)
    return            : (Bool) True if the provider has capacity

=cut

sub overcommitted {
    my ($self, $with_extra) = @_;
    $with_extra //= 0;

    my $sum = $self->assignment_sum() // 0;
    return ( $sum + $with_extra ) > $self->size;
}

=head2 has_capacity($with_extra)

Check if this provider has capacity (optionally including extra usage).

    param $with_extra : (Int) Extra usage (size)
    return            : (Bool) True if the provider has capacity

=cut

sub has_capacity {
    my ($self, $with_extra) = @_;
    $with_extra //= 0;

    return not $self->overcommitted($with_extra);
}

=head2 assign(%data)

Create an assignment for an assignment group:

    my $assignment = $provider->assign(
        assignmentgroup_id => 1,
        size               => 12,
        committed          => 0,
    );

    param %data : (Hash) Hash containing Assignment parameters
    return      : (Assignment) Assignment record

=cut

sub assign {
    my ($self, %data) = @_;
    state $assign_req = [qw( assignmentgroup_id size )]; # required args

    for my $req (@$assign_req) {
        die "Missing assign arg: $req\n" unless exists $data{$req};
    }
    $data{committed} //= 0;

    if ( $self->overcommitted($data{size}) ) {
        die sprintf(
            "No capacity for provider %s (%s) to add %s units",
            $self->provider_id, $self->providertype_name, $data{size}
        );
    }

    return $self->result_source->schema->txn_do(sub {
        my $assignment = $self->result_source->schema->resultset('Assignment')->create({
            provider_id        => $self->provider_id,
            assignmentgroup_id => $data{assignmentgroup_id},
            size               => $data{size},
            committed          => $data{committed},
            resource_id        => $data{resource_id} // undef,
        });
        # confirm we haven't maxed out
        my $sum = $self->assignment_sum();
        if ($sum > $self->size) {
            die sprintf(
                "Overallocated provider %s by %s, rolling back\n",
                $self->provider_id, ( $sum - $self->size ),
            );
        }
        # confirm we don't have a negative sum
        if ($sum < 0) {
            die sprintf("Negative allocation for provider %s", $self->provider_id);
        }

        return $assignment;
    });
}

1;
