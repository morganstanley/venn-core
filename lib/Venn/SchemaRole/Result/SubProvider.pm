package Venn::SchemaRole::Result::SubProvider;

=head1 NAME

package Venn::Schema::ResultSet::SubProvider

=head1 DESCRIPTION

Role for SubProvider to handle CRUD and etc. for SubProvider (P_*) tables

=head1 SYNOPSIS

Adding this Role to a P_* class does quite a lot of common
setup for your Result class, like:
 * loads Validator component (eg.: checking for a valid hostname)
 * adds C<provider_id> field as the first column in the table
 * sets primary_key on C<provider_id> column
 * adds a unique index on C<provider_id> column
 * adds a unique index on the primary_field
 * adds belongs_to relation to Venn::Schema::Result::Provider as 'C<provider>'
 * adds belongs_to relation to Venn::Schema::Result::Provider as
   'C<${self->providertype}_provider>'
 * adds has_many relation to Venn::Schema::Result::Assignment as 'C<assignments>'

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

=head1 METHODS

=cut

use Moose::Role;

=head2 around $row->update()

Wraps the update method to properly serialize columns when needed, so
it won't end up updating virtual attributes which are not physical DB
columns.

=cut

around 'update' => sub {
    my ($orig, $self, $data) = @_;

    for my $col (keys %$data) {
        if ($self->can($col)) {
            my $val = delete $data->{$col};
            $self->$col($val);
        }
    }
    return $self->$orig($data);
};

=head2 assignment_sum()

Returns the sum of all assignments for this provider.

    return : (Num) Sum of assignments

=cut

# TODO: committed option ?
sub assignment_sum {
    my ($self) = @_;

    return $self->assignments->get_column('size')->sum() // 0;
}

=head2 around __PACKAGE__->add_columns(@columns)

Adds class setup magic at column creation time. For details, please check
SYNOPSIS above.

=cut

around 'add_columns' => sub {
    my ($orig, $self, @columns) = @_;

    $self->load_components(qw/DefaultColumnValues Validator/);

    unshift @columns,
      provider_id => {
          display_name   => 'Provider ID',
          is_foreign_key => 1,
          data_type      => 'integer',
          documentation  => 'Provider ID FK',
      };

    # process custom fields, like default_value & validators
    for my $col (@columns) {
        next unless ref $col;

        if (my $default = delete $col->{default_value}) {
            $col->{default_value_sub} = sub { $default };
        }
        if (my $validator = $col->{validate}) {
            unless (ref($validator) eq 'CODE') {
                $validator =~ s/^\\&//;
                my $subname = $self.'::'.$validator;
                $col->{validate} = \&$subname;
            }
        }
    }

    $self->$orig(@columns);

    $self->set_primary_key('provider_id');

    my ($idxname) = $self =~ /::(\w+)$/;
    $idxname = lc $idxname;
    $idxname =~ s/[^a-z0-9]//;
    $self->indices({ "p_${idxname}_pk_idx" => [qw( provider_id )] });

    $self->add_unique_constraint(
        "uc_${idxname}_".$self->primary_field => [$self->primary_field]);

    $self->belongs_to(
        $self->providertype.'_provider' => 'Venn::Schema::Result::Provider',
        'provider_id',
        {
            on_delete => 'restrict',
            on_update => 'restrict',
        },
    );

    $self->belongs_to(
        'provider' => 'Venn::Schema::Result::Provider',
        'provider_id',
        {
            proxy     => [qw/ state_name providertype_name available_date size overcommit_ratio /],
            cascade_update => 1,
            is_foreign_key_constraint => 1,

            on_delete      => 'cascade',
            on_update      => 'restrict',
        },
    );

    $self->has_many(
        'assignments' => 'Venn::Schema::Result::Assignment',
        'provider_id',
    );

    if ((my $container_class = $self->container_class) &&
          (my $container_field = $self->container_field)) {

        $self->belongs_to(
            'container' => 'Venn::Schema::Result::'.$container_class,
            { "foreign.$container_field" => "self.$container_field" },
            {
                on_delete      => 'restrict',
                on_update      => 'restrict',
            },
        );
    }

    return $self;
};

1;
