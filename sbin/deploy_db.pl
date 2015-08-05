#!/usr/bin/env perl

=head1 NAME

deploy_db.pl - Deploy database

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
use warnings;

use FindBin ();
use lib "$FindBin::Bin/../lib";

use Venn::Dependencies;
use Venn::Schema;

use SQL::Translator;
use Try::Tiny;

my $schema = Venn::Schema->env_connect();

say '=== Venn DB Deployment ===';
say ' Environment: ' . $schema->environment;
say ' Drop Tables: ' . $ENV{VENN_DROP_TABLES} ? 'yes' : 'no';
say '';
say 'Press enter to continue...';
my $wait = <>;

my $drop = $ENV{VENN_DROP_TABLES} // 0;
say 'Deploying...';
try {
    $schema->deploy({ add_drop_table => $drop });
}
catch {
    warn "Error deploying: $_\n";
};
say 'Done';
