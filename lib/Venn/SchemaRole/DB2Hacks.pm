package Venn::SchemaRole::DB2Hacks;

=head1 NAME

Venn::SchemaRole::DB2Hacks

=head1 DESCRIPTION

MS DB2 hacks for DBIx::Class

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

use v5.14;
use Moose::Role;

=head2 after sqlt_deploy_hooks($source, $sqlt_schema)

Run our DB2 deploy fixes.

=cut

after 'sqlt_deploy_hook' => sub {
    my ($source, $sqlt_schema) = @_;

    if (Venn::Schema->storage_type =~ /db2/i ) {
        _db2_fixes_deploy_hook($source, $sqlt_schema);
    }
};

=head2 _db2_fixes_deploy_hook($source, $sqlt_schema)

Fix bugs in how SQL::Translator handles DB2

=cut

sub _db2_fixes_deploy_hook {
    my ( $source, $sqlt_schema ) = @_;

    # fix horrible things about db2 in dbix
    foreach my $table ( $sqlt_schema->get_tables ) {
        foreach my $constraint ( $table->get_constraints ) {
            next if ( $constraint->type ne 'FOREIGN KEY' );

            # useful method for db dump and loads where you need to deploy w/o constraints
            if ( $ENV{VENN_DEPLOY_NO_CONSTRAINTS} ) {
                $table->drop_constraint($constraint);
                next;
            }

            # SQL::Translator gets the constraint names wrong
            $constraint->on_delete('ON DELETE ' . $constraint->on_delete) if $constraint->on_delete;

            # no cascade updates ( not supported in db2 )
            if ( $constraint->on_update =~ /^cascade/i ) {
                die "DB2 doesn't support ON UPDATE CASCADE for table $table and constraint " . $constraint->name;
            }

            elsif ($constraint->on_update) {
                $constraint->on_update('ON UPDATE ' . $constraint->on_update);
            }

        }
        #hack because db2 auto-creates indexes on unique constraints, and so does
        #sql translate - causing errors. let db2 do it.
        for my $index ( $table->get_indices ) {

            for my $uc ( $table->unique_constraints ) {
                $table->drop_index($index->name) if @{$index->fields} ~~ @{$uc->field_names};
            }
        }
    }
    return;
}

=head2 lower_optimization_class($optimization_class)

=head2 lower_optimization_level($optimization_class)

Lowers the query optimization level for DB2.
Defaults to 2

See: http://publib.boulder.ibm.com/infocenter/db2luw/v8/advanced/content.jsp?topic=/com.ibm.db2.udb.doc/admin/r0001007.htm

=cut

*lower_optimization_level = \&lower_optimization_class;
sub lower_optimization_class {
    my ($self, $optimization_class) = @_;

    return $self->set_optimization_class($optimization_class // 2);
}

=head2 raise_optimization_class($optimization_class)

=head2 raise_optimization_level($optimization_class)

Raises the query optimization level for DB2.
Defaults to 5

See: http://publib.boulder.ibm.com/infocenter/db2luw/v8/advanced/content.jsp?topic=/com.ibm.db2.udb.doc/admin/r0001007.htm

=cut

*raise_optimization_level = \&raise_optimization_class;
sub raise_optimization_class {
    my ($self, $optimization_class) = @_;

    return $self->set_optimization_class($optimization_class // 5);
}

=head2 set_optimization_class($optimization_class)

=head2 set_optimization_level($optimization_class)

Sets the query optimization level for DB2.
Defaults to 5

See: http://publib.boulder.ibm.com/infocenter/db2luw/v8/advanced/content.jsp?topic=/com.ibm.db2.udb.doc/admin/r0001007.htm

=cut

*set_optimization_level = \&set_optimization_class;
sub set_optimization_class {
    my ($self, $optimization_class) = @_;
    $optimization_class //= 5;

    if ( $self->storage_type =~ /db2/i ) {
        return $self->storage->dbh_do(
            sub {
                my ($storage, $dbh) = @_;
                $dbh->do("set current query optimization $optimization_class");
            }
        );
    }
    return;
}

1;
