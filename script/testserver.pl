#!/usr/bin/env perl

=head1 NAME

testserver.pl

=head1 SYNOPSIS

./testserver.pl [--options] [port]

=head1 OPTIONS

    -d --debug           force debug mode
    -f --fork            handle each request in a new process
                         (defaults to false)
    -? --help            display this help and exits
    -h --host            host (defaults to all)
    -p --port            port (defaults to 3000)
    -k --keepalive       enable keep-alive connections
    -r --restart         restart when files get modified
                         (defaults to false)
    -rd --restart_delay  delay between file checks
                         (ignored if you have Linux::Inotify2 installed)
    -rr --restart_regex  regex match files that trigger
                         a restart when modified
                         (defaults to '\.yml$|\.yaml$|\.conf|\.pm$')
    --restart_directory  the directory to search for
                         modified files, can be set multiple times
                         (defaults to '[SCRIPT_DIR]/..')
    --follow_symlinks    follow symlinks in search directories
                         (defaults to false. this is a no-op on Win32)
    --background         run the process in the background
    --pidfile            specify filename for pid file

See also:

    perldoc Catalyst::Manual
    perldoc Catalyst::Manual::Intro

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

use strict;
use warnings;
use 5.010;

use File::Basename;

my $start_script = "venn_server.pl";
my $listen_port = $ARGV[0] // 3000;

#Usage:
#    venn_server.pl [options]
#

my $path = dirname $0;

my $server = sprintf( "%s/%s", $path, $start_script );

my @execline = ( $server, "-d", "-p", $listen_port );
push @execline, "-r" unless $ENV{VENN_TEST_NO_AUTO_RESTART};

say "Running: " . join( ' ', @execline );

exec @execline;
