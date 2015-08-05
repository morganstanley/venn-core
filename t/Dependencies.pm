package t::Dependencies;

use v5.14;
use warnings;

our %DEPENDENCIES;

BEGIN {
    %DEPENDENCIES = (
        'Pod::Coverage'       => '0.21',
        'Devel::Symdump'      => '2.08',
        'Test::Pod'           => '1.45',
        'Test::Pod::Coverage'  => '1.08',
        'Test::Most'          => '0.21',
        'Exception::Class'    => '1.32', # Used by Test::Most::Exception
        'Class::Data::Inheritable' => '0.08', # Used by Exception::Class::Base
        'Devel::StackTrace'   => '1.27', # Used by Exception::Class::Base
# ** $isa missing. Used by Exception::Class
        'Test::Differences'   => '0.4801',# Used by Test::Most
        'Text::Diff'          => '1.37', # Used by Test::Differences
        'Algorithm::Diff'     => '1.1902',# Used by Text::Diff
        'Test::Exception'     => '0.32', # Used by Test::Most
        'Sub::Uplevel'        => '0.22', # Used by Test::Exception
        'Test::Deep'          => '0.110',# Used by Test::Most
        'Test::Warn'          => '0.24', # Used by Test::Most
        'Tree::DAG_Node'      => '1.12', # Used by Test::Warn
        'Data::Dumper::Names'  => '0.03', # Used by Test::Most
        'PadWalker'          => '1.92', # Used by Data::Dumper::Names


# JSON
        'JSON::XS'            => '2.32',
        'common::sense'       => '3.6',

# Test::Perl::Critic
        'Test::Perl::Critic'   => '1.01',
        'Perl::Critic'        => '1.116',# Used by Test::Perl::Critic
        'Readonly'           => '1.03',
        'Readonly::XS'        => '1.05',
        'List::MoreUtils'     => '0.33',
        'Config::Tiny'        => '2.14',
        'PPI'                => '1.215',
        'Params::Util'        => '1.04',
        'Clone'              => '0.31',
        'IO::String'          => '1.08',
        'Class::XSAccessor'   => '1.18',
        'PPIx::Utilities'     => '1.001000',
        'PPIx::Regexp'        => '0.020',
        'String::Format'      => '1.16',
        'B::Keywords'         => '1.10',
        'Email::Address'      => '1.892',
        'Pod::Spell'          => '1.01',

# Perl::Tidy
        'Perl::Tidy'          => '20101217',

# For App::Cmd testing
        'IO::TieCombine'      => '1.000',

        'Carp::Always'        => '0.09',

# for Catalyst standalone testing
        'Test::TCP'           => '2.02',
        'Test::Generated'     => '0.2',

# LWP suite
        'libwww::perl'        => '6.04',
        'HTTP::Message'       => '6.06', # HTTP::Request used by LWP::UserAgent
        'HTTP::Date'          => '6.00', # Used by LWP::UserAgent
        'URI'                => '1.60', # Used by HTTP::Config, HTTP::Request::Common
        'Net::HTTP'           => '6.01',
    );
}

## no critic BuiltinFunctions::ProhibitStringyEval

BEGIN {
    # venn core test local dependencies
    eval 'use t::LocalDependencies';
    # venn test implementation-specific dependencies
    eval 'use t::ImplementationDependencies';
}

## use critic

1;
