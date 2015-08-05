#!env perl
#-*- mode: CPerl;-*-

use v5.14;
use warnings;

=head1 NAME

generate_swagger_documentation.pl - simple re-generator of API documentation

=head1 DESCRIPTION

It will recurse all files in lib/Venn/Controller/API/v1, parse POD and generate
Swagger-compatible documentation into root/swagger/api-docs.json

Enable debugging output with: export DEBUG=1

Usage: generate_swagger_documentation.pl [<section to filter>]
section could be any top-level API element, like: attribute, provider, etc.

Filtering has been added just for debugging purposes.

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

BEGIN {
    use FindBin qw($Bin);
    use lib "$Bin/../lib";
}

use Swagger::Tools::Dependencies;
use Swagger::Tools::PODParser;

use Getopt::Long;
use Path::Class qw(dir);

our $OUTFILE = dir($Bin)->parent->subdir(qw(root swagger))->file('api-docs.json');

my $filter = $ARGV[0];

our $generator = Swagger::Tools::PODParser->new(
    base_path => '/api/v1',
    info => {
        "title" => "Venn",
        "description" => "Resource and placement allocation.",
        "contact" => {
            "name" => 'Venn Dev <venn-dev@morganstanley.com>',
            "url" => 'http://venn/',
            "email" => 'venn_dev@morganstanley.com',
        },
        "version" => "2.0.0",
    },
    debug => $ENV{DEBUG},
);

my $dir = dir($Bin)->parent->subdir(qw(lib Venn Controller API v1));

$generator->pod_dir($dir);

my $structure = $generator->structure;

if ($filter) {
    map { delete $structure->{paths}{$_} } grep !/$filter/, keys %{$structure->{paths}};
}

my $encoder = JSON::XS->new->ascii->pretty;
open my $outfh, '>', $OUTFILE or die "Can't open outfile $OUTFILE: $!";
print $outfh $encoder->encode($structure);
close $outfh;

warn "Generated ".scalar(keys %{$structure->{paths}}). " endpoints into file $OUTFILE\n";
