package Venn::Dependencies;

use v5.14;
use warnings;

=head1 NAME

Venn::Dependencies

=head1 DESCRIPTION

Library dependency declarations.

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

our %DEPENDENCIES;

BEGIN {
    %DEPENDENCIES = (
        # resolved catalyst dependencies for 5.14
        'Data::Dump'          => '1.22', # up from 1.19
        'URI'                => '1.65', #up from 1.58
        'HTTP::Message'       => '6.06', #up from 6.02
        'Path::Class'         => '0.32', #up from 0.23
        'Text::SimpleTable'   => '2.03', #up from 0.05
        #############################################

        'Catalyst::Runtime'   => '5.90082',
        # TODO: upgrading to a newer Moose causes some issues. investigate this.
        #'Moose'              => '2.1403', # Used by Catalyst - newer TryCatch
        'Moose'              => '2.0604', # Used by Catalyst - newer TryCatch
        'Package::DeprecationManager' => '0.11', # Used by Moose::Deprecated
        'Sub::Install'        => '0.925', # Used by Package::DeprecationManager, Package::DeprecationManager
        'Sub::Exporter'       => '0.982', # Used by Moose::Exporter
        'MRO::Compat'         => '0.12', # Used by Class::MOP, Class::C3::Adopt::NEXT, Moose::Object
        'Mouse'              => '1.01', # Class::C3 may be used by MRO::Compat
        'Eval::Closure'       => '0.06', # Used by Class::MOP::Method::Generated
        'Sub::Name'           => '0.05', # Used by Class::MOP, Moose::Meta::TypeConstraint
        'Params::Util'        => '1.07', # Used by Data::OptList, Moose::Util
        'Variable::Magic'     => '0.46', # Used by B::Hooks::EndOfScope
        'IO'                 => '1.25', # IO::Socket used by Catalyst::Request
        'HTTP::Date'          => '6.00', # Used by HTTP::Headers
        'Time::Zone'          => '1.20', # Time::Zone may be used by HTTP::Date
        'Encode::Locale'      => '1.02', # May be used by HTTP::Response
        'String::RewritePrefix' => '0.006', # Used by Catalyst::Utils
        'Term::Size::Any'      => '0.001',   # Used by Catalyst::Utils
        'Term::Size::Perl'     => '0.029', # May be used by Term::Size::Any
        'MooseX::MethodAttributes' => '0.24', # Used by Catalyst::Controller
        'Tree::Simple'        => '1.18', # Used by Catalyst
        'Tree::Simple::VisitorFactory' => '0.10', # Tree::Simple::Visitor::FindByUID used by Catalyst
        'Class::C3::Adopt::NEXT' => '0.13',        # Used by Catalyst
        'Catalyst::Devel'     => '1.31', # May be used by Catalyst
        'Devel::OverloadInfo' => '0.002',
        'Stream::Buffered'    => '0.02',
        'Hash::MultiValue'    => '0.08',
        'Safe::Isa'           => '1.000003',
        'Plack'               => '1.0033',
        'Plack::Middleware::ReverseProxy' => '0.15',
        'Plack::Middleware::MethodOverride' => '0.10',
        'Plack::Middleware::RemoveRedundantBody' => '0.05',
        'Plack::Middleware::FixMissingBodyInRedirect' => '0.12',
        'Crypt::SSLeay'        => '0.12',
        'List::Util'           => '1.41',


        # manually added catalyst requirements
        'Catalyst::Model::DBIC::Schema' => '0.65',
        'MooseX::Types::LoadableClass' => '0.012',
        'namespace::autoclean' => '0.13',
        'namespace::clean'    => '0.21',
        'CGI::Simple'         => '1.113',
        'HTTP::Body'          => '1.12',
        'MooseX::Emulate::Class::Accessor::Fast' => '0.00903',
        'MooseX::Types::Common' => '0.001002',
        'MooseX::Types'       => '0.25',
        'Carp::Clan'          => '6.04',
        'MooseX::Getopt'      => '0.58',
        'Getopt::Long::Descriptive' => '0.092', # Used by MooseX::Getopt::GLD
        'Params::Validate'    => '1.00', # Used by Getopt::Long::Descriptive
        'MooseX::Role::WithOverloading' => '0.09',
        'aliased'            => '0.30',
        'File::ChangeNotify'  => '0.20',
        'MooseX::SemiAffordanceAccessor' => '0.09',
        'MooseX::Params::Validate' => '0.16',
        'Devel::Caller'       => '2.05',
        'Catalyst::Plugin::Static::Simple' => '0.33',
        'MIME::Types'         => '1.31',
        'Catalyst::Plugin::ConfigLoader' => '0.30',
        'Config::Any'         => '0.23',
        'Data::Visitor'       => '0.27',
        'Tie::ToObject'       => '0.03',
        'Config::General'     => '2.50',
        'Catalyst::Action::RenderView' => '0.16',
        'PadWalker'          => '1.92',
        'CatalystX::Component::Traits' => '0.16',
        'MooseX::Traits::Pluggable' => '0.10',
        'Module::Find'        => '0.06',
        'Data::Compare'       => '1.22',
        'Catalyst::Plugin::Unicode::Encoding' => '1.2',
        'Catalyst::Plugin::Authentication' => '0.10017',
        'Catalyst::Plugin::Redirect' => '0.02',

        # FastCGI Engine
        'FCGI'               => '0.74', # Used by Catalyst::Engine::FastCGI

        # dbix::class
        'DBIx::Class'        => '0.08270',
        'Class::C3::Componentised' => '1.001000', # Used by DBIx::Class::Componentised
        'Class::Accessor::Grouped' => '0.10010',
        'DBIx::Class::InflateColumn::Serializer' => '0.06',
        'DBIx::Class::Helpers' => '2.018002',

        # for deploying
        'SQL::Translator'     => '0.11016',
        'Class::Method::Modifiers' => '2.04',
        'Role::Tiny'          => '1.003001',
        'Package::Variant'    => '1.001004',
        'Heap'               => '0.80',
        'Class::Base'         => '0.03',
        'Digest::SHA1'        => '2.13',
        'Class::Data::Inheritable' => '0.08',
        'Class::MakeMethods'  => '1.01',
        'DBIx::Class::Helpers' => '2.018002',

        # MooseX modules that we're actively using
        'MooseX::ClassAttribute' => '0.24',
        'MooseX::NonMoose'    => '0.17',
        'MooseX::Singleton'   => '0.26',

        # TODO: Get newer version + StackTrace::Auto
        'Throwable'          => '0.101110',
        'Module::Runtime'     => '0.014',
        'Import::Into'        => '1.001001',

        # Sub Quote
        'Moo'                => '1.003000',
        'strictures'         => '1.004004',
        'Context::Preserve'   => '0.01',
        'DBI'                => '1.624',

        # AutoCRUD
        'Catalyst::Plugin::AutoCRUD' => '0.68',
        'JSON::Any'           => '1.25', # May be used by Catalyst::View::JSON
        'JSON'               => '2.51', # May be used by JSON::Any
        'Catalyst::View::JSON' => '0.32', # Used by Catalyst::Plugin::AutoCRUD
        'Hash::Merge'         => '0.12',
        'SQL::Abstract'       => '1.74', #was 1.72
        'Data::Page'          => '2.02',

        # Catalyst::View::TT
        'Catalyst::View::TT'  => '0.36',
        'Template'            => '2.25',
        'Template::Timer'     => '1.00',

        # SQLite
        'DBD::SQLite'         => '1.37',

        # Config loading from YAML::XS
        'YAML::XS' => '0.41',

        # Data::UUID
        'Data::UUID' => '1.217',

        # rest api
        'Catalyst::Controller::DBIC::API' => '2.003001',
        'Catalyst::Controller::ActionRole' => '0.15',
        'CGI::Expand'         => '2.03', # Used by Catalyst::Controller::DBIC::API
        'Test::Deep'          => '0.108',
        'MooseX::Role::Parameterized' => '1.08',
        'Data::DPath::Validator' => '0.093411',
        'Data::DPath'         => '0.44',
        'Iterator::Util'      => '0.02',
        'Iterator'           => '0.03',
        'Exception::Class'    => '1.32',
        'Devel::StackTrace'   => '2.00',
        'MooseX::Role::BuildInstanceOf' => '0.07',
        'MooseX::Types::Structured' => '0.26',
        'Devel::PartialDump'  => '0.15',
        'Catalyst::Action::REST' => '0.90',
        'Catalyst::ActionRole::MatchRequestMethod' => '0.03',
        'Perl6::Junction'     => '1.40000',

        # json::xs
        'JSON::XS'            => '2.32',
        'common::sense'       => '3.6',

        # serialization (for REST)
        'Data::Serializer' => '0.59',

        'Data::Dumper::Concise' => '2.020',

        # Validation
        'Mouse'              => '1.01', # Class::C3 may be used by MRO::Compat
        'Class::Inspector'    => '1.28', # Used by Class::Accessor::Grouped, FormValidator::Simple
        'Sub::Name'           => '0.05', # May be used by Class::Accessor::Grouped
        'FormValidator::Simple' => '0.22', # Used by DBIx::Class::Validation
        'Date::Calc'          => '6.3', # Used by FormValidator::Simple::Validator
        'Carp::Clan'          => '6.04', # Used by Date::Calc
        'Email::Valid'        => '0.185', # Used by FormValidator::Simple::Validator
#    'MailTools'          => '1.59', # Mail::Address used by Email::Valid
        'Net::DNS'            => '0.66', # May be used by Email::Valid
        'DateTime::Format::Strptime' => '1.5000', # Used by FormValidator::Simple::Validator
        'DateTime'           => '0.70', # Used by DateTime::Format::Strptime
        'DateTime::Format::Epoch' => '0.13',
        'Math::Round'         => '0.06', # Used by DateTime
        'DateTime::Locale'    => '0.45', # Used by DateTime
        'DateTime::TimeZone'  => '1.36', # Used by DateTime
        'Class::Load'         => '0.20', # Used by DateTime::TimeZone::Local
        'Data::OptList'       => '0.108', # Used by Class::Load
        'Module::Implementation' => '0.07', # Used by Class::Load
        'Try::Tiny'           => '0.22', # Used by Class::Load
        'Params::Validate'    => '1.00', # Used by DateTime::Format::Strptime
        'List::MoreUtils'     => '0.405', # Used by FormValidator::Simple::Results, FormValidator::Simple::Validator
        'Email::Valid::Loose'  => '0.05', # Used by FormValidator::Simple::Validator
        'Tie::IxHash'         => '1.22', # Used by FormValidator::Simple::Results
        'UNIVERSAL::require'  => '0.11', # Used by FormValidator::Simple
        'YAML'               => '0.72', # Used by FormValidator::Simple::Messages
        'Class::Accessor'     => '0.34', # Class::Accessor::Fast used by FormValidator::Simple
        'Class::Data::Accessor' => '0.04004', # Used by FormValidator::Simple
        'Class::Singleton'    => '1.4',
        'Data::FormValidator' => '4.66',
        'Perl6::Junction'     => '1.40000', # Used by Data::FormValidator
        'Regexp::Common'      => '2010010201', # May be used by Data::FormValidator::Results, Data::FormValidator::Constraints
        'IntervalTree'       => '0.05',  # used by Placementengine/Helper/Ports.pm

        'IPC::Run'            => '0.91',

        # AQ Cache
        'Cache::Cache'        => '1.06',
        'Digest::SHA1'        => '2.13',
        'Error'              => '0.17016',

        # Logging
        'Log::Log4perl'       => '1.43',
        'Convert::ASN1'       => '0.22', # Used by Net::LDAP
        'IO::Socket::SSL'      => '1.38',     # May be used by Net::LDAP
        'Net::SSLeay'         => '1.42', # Used by IO::Socket::SSL
        'Socket6'            => '0.23', # May be used by IO::Socket::SSL
        'LWP'                => '6.04', # LWP::UserAgent may be used by Log::Log4perl::Config
        'IO::HTML'            => '1.00', # May be used by HTTP::Message
        'LWP::MediaTypes'     => '6.01', # May be used by HTTP::Request::Common
        'HTTP::Cookies'       => '6.00', # May be used by LWP::UserAgent
        'XML::DOM'            => '1.44', # May be used by Log::Log4perl::Config
#    'XML::RegExp'        => '1.02', # XML::RegExp used by XML::DOM
        'XML::Parser'         => '2.41', # May be used by XML::DOM
        'Log::Dispatch'            => '2.26',
        'Log::Dispatch::FileRotate' => '1.19',
        'Date::Manip' => '6.42',

        #float conversion
        'Data::Types'         => '0.09',

        # TryCatch
        'TryCatch'           => '1.003002',
        'Devel::Declare'      => '0.006011', # Used by TryCatch
        'B::Hooks::OP::Check'   => '0.19', # Used by Devel::Declare
        'B::Hooks::EndOfScope' => '0.12',     # Used by TryCatch
        'Variable::Magic'     => '0.52',
        'Sub::Exporter::Progressive' => '0.001011', # Used by B::Hooks::EndOfScope
        'B::Hooks::OP::PPAddr'  => '0.03',        # Used by TryCatch
        'Parse::Method::Signatures' => '1.003012', # Used by TryCatch
        'Devel::GlobalDestruction' => '0.11', # Used by Moose::Meta::Role, Moose::Object
        'Package::Stash'      => '0.34', # Used by Class::MOP::Package
        'PPI'                => '1.215', # Used by Parse::Method::Signatures
        'Clone'              => '0.38', # Used by PPI::Token::Whitespace, PPI::Element
        'IO::String'          => '1.08', # Used by PPI::Token::Data
        'Class::XSAccessor'   => '1.19', # Used by PPI::Document::Fragment, PPI::Document::Normalized, PPI::Document::File
        'Scope::Upper'        => '0.16', # Used by TryCatch
        'MooseX::Traits'      => '0.11',

        # Devel::SimpleTrace
        'Devel::SimpleTrace'  => '0.08',

        # Lingua::EN::Inflect::Phrase
        'Lingua::EN::Inflect::Phrase' => '0.04',
        'Lingua::EN::Inflect::Number' => '1.1', # Used by Lingua::EN::Inflect::Phrase
        'Lingua::EN::Inflect'  => '1.893', # Used by Lingua::EN::Inflect::Number
        'Lingua::EN::Tagger'   => '0.16', # Used by Lingua::EN::Inflect::Phrase
        'HTML::Parser'        => '3.71', # HTML::TokeParser used by Lingua::EN::Tagger
        'HTML::Tagset'        => '3.20', # Used by HTML::TokeParser
        'Lingua::Stem'        => '0.84', # Lingua::Stem::En used by Lingua::EN::Tagger

        #From CatalystScriptDepends
        'Algorithm::C3'       => '0.07', #unique
        'Any::Moose'          => '0.11', #unique
        'Catalyst::Model::DBI' => '0.15', #unique
        'Class::C3'           => '0.20', #unique
        'Class::C3::XS'        => '0.13', #unique
        'Compress::Raw::Bzip2' => '2.062', #unique
        'Compress::Raw::Zlib'  => '2.062', #unique
        'Data::Alias'         => '1.15', #unique
        'File::Modified'      => '0.07', #unique
        'File::ShareDir'      => '1.00', #unique
        'File::Slurp'         => '9999.13',
        'HTTP::Request::AsCGI' => '1.2', #unique
#    'IO::Compress'        => '2.030', #unique
        'Module::Pluggable'   => '3.8', #unique
        'Sub::Identify'       => '0.04', #unique
        'Sub::Uplevel'        => '0.2002', #unique
        'Task::Weaken'        => '1.02', #unique
        'Test::Exception'     => '0.29', #unique
        'Text::CSV_XS'        => '0.95', #unique
        'UNIVERSAL::can'      => '1.12', #unique
        'UNIVERSAL::isa'      => '1.01', #unique
        'XML::NamespaceSupport' => '1.09', #unique
        'XML::SAX'            => '0.96', #unique
        'XML::Simple'         => '2.18', #unique
        'YAML::Tiny'          => '1.39', #unique

        # Test::Perl::Critic
        'Test::Perl::Critic'  => '1.01',
        'Perl::Critic'        => '1.116',# Used by Test::Perl::Critic
        'Readonly'            => '2.00', # Used by Perl::Critic::Utils
        'Readonly::XS'        => '1.05', # Used by Readonly
        'B::Keywords'         => '1.10', # Used by Perl::Critic::Utils
        'Exporter::Tiny'      => '0.042',# Used by List::MoreUtils
        'Config::Tiny'        => '2.20',
        'String::Format'      => '1.16',
        'PPIx::Utilities'     => '1.001000',
        'PPIx::Regexp'        => '0.020',
        'Perl::Tidy'          => '20140711',
        'Pod::Spell'          => '1.01',
        'Email::Address'      => '1.892',

        # Not sure how you want to annotate these...
        'Data::Walk'          => 0,
        'Test::Most'          => 0,

    );
}

## no critic BuiltinFunctions::ProhibitStringyEval

BEGIN {
    # venn core local dependencies
    eval 'use Venn::LocalDependencies';
    # venn implementation-specific dependencies
    eval 'use Venn::ImplementationDependencies';
}

## use critic

1;
