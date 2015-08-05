package DBIx::Class::DefaultColumnValues;

=head1 NAME

DBIx::Class::DefaultColumnValues - Automatically set column default values on insert

=head1 SYNOPSIS

  package My::Schema::SomeTable;

  __PACKAGE__->load_components(qw/ColumnDefault Core/);

  __PACKAGE__->add_columns(
      created => {
          date_type         => 'timestamp',
          default_value_sub => sub { time() },
      },
      updated => {
          date_type        => 'timestamp',
          update_value_sub => sub { time() },
      },
  );

=cut

use 5.010;
use strict;
use warnings;

=head1 METHODS

=head2 insert(@args)

Set default values when inserting or updating a record.

    param @args : (Array) Passthrough args for base insert

=cut

sub insert {
    my ($self, @args) = @_;

    my $colinfo = $self->result_source->columns_info;
    for my $column (keys %$colinfo) {
        my $info = $colinfo->{$column};
        next if $info->{is_auto_increment};

        my $update_value;
        if (! $self->in_storage) {
            next if $self->has_column_loaded($column); # skip if loaded from db or set locally

            my $dv = $info->{default_value_sub};
            if (defined $dv && ref($dv) eq 'CODE') {
                $update_value = $dv->($self);
            }
        }
        else {
            my $uv = $info->{update_value_sub};
            if (defined $uv && ref($uv) eq 'CODE') {
                $update_value = $uv->($self);
            }
        }

        if (defined $update_value) {
            my $accessor = $info->{accessor} || $column;
            $self->$accessor($update_value);
        }
    }

    return $self->next::method(@args);
}

1;
