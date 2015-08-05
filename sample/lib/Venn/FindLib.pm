package Venn::FindLib;

=head1 NAME

Venn::FindLib

=head SYNOPSIS

use Venn::FindLib;

=head1 DESCRIPTION

Calls "use lib" on the Venn Core directory and sets the VENN_CONF_DIR to the test suite.

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

use Path::Class qw(file dir);

our $CORE_LIB_DIR;

# ../../../../t/conf

BEGIN {
    my $current_dir = file(__FILE__)->dir->resolve;
    my $core_dir = $current_dir->parent->parent->parent->resolve;
    my $conf_dir = $core_dir->subdir('t')->subdir('conf')->resolve->stringify;
    $core_dir = $core_dir->resolve->stringify;

    warn "Venn core directory: " . $core_dir . "\n";
    warn "Venn config directory: " . $conf_dir . "\n";

    $CORE_LIB_DIR = $core_dir . "/lib" if -d $core_dir . "/lib";

    $ENV{VENN_CONF_DIR} = $conf_dir;
}

BEGIN {
    use lib $CORE_LIB_DIR;
}

1;
