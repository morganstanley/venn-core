package Venn::SchemaRole::Result::NamedResource;

=head1 NAME

package Venn::Schema::ResultSet::NamedResource

=head1 DESCRIPTION

Role for Named Resources to NamedResource (NR_*) tables

=head1 SYNOPSIS

Adding this Role to a NR_* class does quite a lot of common
setup for your Result class, like:
 * loads Validator component (eg.: checking for a valid hostname)
 * adds C<resource_id> and C<provider_id> field as first columns in the table
 * sets primary_key on C<resource_id> column
 * adds indices on C<resource_id> and C<provider_id> columns
 * adds a unique index on the C<provider_id, primary_field> columns
 * adds belongs_to relation to Venn::Schema::Result::Provider as 'C<provider>'
 * adds has_many relation to Venn::Schema::Result::Assignment as 'C<assignment>'

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

=head2 around __PACKAGE__->add_columns(@columns)

Adds class setup magic at column creation time. For details, please check
SYNOPSIS above.

=cut

around 'add_columns' => sub {
    my ($orig, $self, @columns) = @_;

    $self->load_components(qw/Validator/);

    unshift @columns,
      resource_id => {
          display_name      => 'Resource ID',
          data_type         => 'integer',
          is_auto_increment => 1,
          documentation     => 'Resource ID',
      },
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

    $self->set_primary_key('resource_id');

    my ($idxname) = $self =~ /::(\w+)$/;
    $idxname = lc $idxname;
    $idxname =~ s/[^a-z0-9]//;
    $self->indices({
        "p_${idxname}_pk_idx"     => ['resource_id'],
        "p_${idxname}_provid_idx" => ['provider_id'],
    });

    $self->add_unique_constraint(
        "uc_${idxname}_".$self->primary_field => ['provider_id', $self->primary_field]);

    $self->belongs_to(
        'provider' => 'Venn::Schema::Result::Provider',
        'provider_id',
        {
            on_delete      => 'cascade',
            on_update      => 'restrict',
        },
    );

    $self->has_many(
        'assignment' => 'Venn::Schema::Result::Assignment',
        {
            'foreign.provider_id' => 'self.provider_id',
            'foreign.resource_id' => 'self.resource_id',
        },
        { is_foreign_key_constraint => 0, },
    );

    return $self;
};

1;
