package Venn;

=head1 NAME

Venn - Catalyst based application

=head1 SEE ALSO

L<Catalyst>

=head1 DESCRIPTION

Venn Catalyst main class

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

our $VERSION = '1.0.0';

use Moose;
use MooseX::ClassAttribute;
use namespace::autoclean;

use Catalyst::Runtime 5.90;

use Scalar::Util qw( blessed reftype );
use Sys::Hostname;
use File::Path qw( make_path );
use JSON::XS;
use Data::Dumper;
use Log::Log4perl;

class_has 'log_base' => (
    is => 'ro',
    isa => 'Str',
    builder => '_build_log_base',
);

sub _build_log_base {
    my $dir;

    my $base = $ENV{VENN_LOG_BASE} // '/var/tmp/venn';

    given ($ENV{VENN_ENV} // 'sqlite') {
        when (/^prod$/i) {
            $dir = sprintf '%s/%s', $base, 'prod';
        }
        when (/^qa$/i) {
            $dir = sprintf '%s/%s', $base, 'qa';
        }
        when (/^dev$/i) {
            $dir = sprintf '%s/%s', $base, 'dev';
        }
        default {
            $dir = '/tmp';
        }
    }

    # ensure we can log there
    make_path($dir);

    return $dir;
}
class_has 'log_file' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '_build_log_file',
);

sub _build_log_file {
    my ($class) = @_;

    my $log_file;
    given ($ENV{VENN_ENV} // 'sqlite') {
        when (/^sqlite$/i) {
            my $user = $ENV{VENN_OVERRIDE_USER} || getlogin || getpwuid($<) || "unknown";
            my $pid = $$;
            $log_file = sprintf("/tmp/venn_%s.log", $user, $pid);
        }
        default {
            $log_file = sprintf "%s/venn_%s.log", $class->log_base, hostname();
        }
    }
    #say STDERR "Logging to: " . $log_file;

    return $log_file;
}

class_has 'logger' => (
    is      => 'ro',
    isa     => 'Venn::Log::L4PWrapper',
    lazy    => 1,
    builder => '_build_logger',
);

sub _build_logger {
    my ($self) = @_;

    require Venn::Log::L4PWrapper;
    return Venn::Log::L4PWrapper->new(Log::Log4perl->get_logger(ref $self));
}

=head1 PLUGINS

Set flags and add plugins for the application.

Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
therefore you almost certainly want to keep ConfigLoader at the head of the
list if you're using it.

        -Debug: activates the debug mode for very useful log messages
  ConfigLoader: will load the configuration from a Config::General file in the
                application's home directory
Static::Simple: will serve static files from the application's root
                directory

=cut

use Catalyst qw/
    ConfigLoader
    Static::Simple
    Authentication
    Redirect
/;

extends 'Catalyst';

=head1 CONFIGURATION

Configure the application.

Note that settings in venn.yml (or other external
configuration file that you set up manually) take precedence
over this when using ConfigLoader. Thus configuration
details given here can function as a default configuration,
with an external configuration file acting as an override for
local deployment.

=cut

my $catalyst_config = 'venn.yml';
$catalyst_config = sprintf "%s/%s", $ENV{CATALYST_HOME}, $catalyst_config if exists $ENV{CATALYST_HOME};

__PACKAGE__->config( 'Plugin::ConfigLoader' => { file => $catalyst_config } );

__PACKAGE__->config->{log}{file}{name} = __PACKAGE__->log_file; # dynamic value

#
# add CORS support & Venn version to response headers
#

before 'finalize_headers' => sub {
    my ($c) = @_;

    my $origin = $c->request->headers->header('Origin') // $c->request->headers->header('ORIGIN')
                 // $c->engine->env->{Origin} // $c->engine->env->{ORIGIN};
    if (defined $origin) {
        $c->response->headers->header('Access-Control-Allow-Headers' => 'Origin, X-Requested-With, Content-Type, Accept');
        $c->response->headers->header('Access-Control-Allow-Methods' => 'HEAD, GET, PUT, POST, DELETE, OPTIONS');
        $c->response->headers->header('Access-Control-Allow-Origin' => $origin);
    }

    $c->response->headers->header('X-Venn-Version', $Venn::VERSION);
};

#
# include the venn version in the log when it starts
#

after 'setup_finalize' => sub {
    my ($self) = @_;

    $self->log->infof("Venn v%s is now ready to handle requests", $Venn::VERSION);
};

#
# add in support for an optional uri prefix (e.g. /venn)
#

around 'prepare' => sub {
    my $orig = shift;
    my $self = shift;
    my ($env, $args) = @_;

    if ($ENV{VENN_PREFIX}) {
        $args->{REQUEST_URI} = $self->fix_path($args->{REQUEST_URI}, $ENV{VENN_PREFIX}) if defined $args->{REQUEST_URI};
        $args->{PATH_INFO}   = $self->fix_path($args->{PATH_INFO}, $ENV{VENN_PREFIX})   if defined $args->{PATH_INFO};
    }

    return $self->$orig(@_);
};

#
# add in CORS support (HACK: i think this may be hacky?)
# TODO: this is duplicate code... look into it
#

before 'finalize' => sub {
    my ($c) = @_;

    if ($c->request->method =~ /options/i) {
        $c->response->content_type('text/plain');
        $c->response->status(200);
        $c->response->body('');
        my $origin = $c->request->headers->header('Origin') // $c->request->headers->header('ORIGIN')
                     // $c->engine->env->{Origin} // $c->engine->env->{ORIGIN};
        if (defined $origin) {
            $c->response->headers->header('Access-Control-Allow-Headers' => 'Origin, X-Requested-With, Content-Type, Accept');
            $c->response->headers->header('Access-Control-Allow-Methods' => 'HEAD, GET, PUT, POST, DELETE, OPTIONS');
            $c->response->headers->header('Access-Control-Allow-Origin' => $origin);
        }
    }
};

#
# Log to the audit log
#

## no critic(Subroutines::ProtectPrivateSubs)
before 'log_response' => sub {
    my $c = shift;

    if ($c->req->method ne 'GET') {
        # Audit the request that we've just processed
        my $req_payload = $c->req->data ? encode_json($c->req->data) : 'none';
        my $res_payload = $c->res->body // 'none';
        my $audit_rs = $c->model("VennDB::Audit");
        my %audit_data = (
            user             => $c->req->remote_user() // 'anonymous',
            uri_path         => $c->req->_path,
            http_method      => $c->req->method,
            request_payload  => $req_payload, # NOTE - this is a modified payload with env/grn/cap deleted
            #request_payload  => $c->{request_payload_stash},
            response_payload => $res_payload,
            response_code    => $c->res->status,
        );
        $audit_rs->create(\%audit_data);
    }
};
## use critic

=head2 $c->fix_path($path, $prefix)

Removes the app prefix /venn from the request.

    param $path   : (Str) the current path (uri)
    param $prefix : (Str) prefix to remove

=cut

sub fix_path {
    my ($self, $path, $prefix) = @_;

    if ($path =~ m!^$prefix/(.*)!) {
        $path = $1;
    }
    return $path;
}

__PACKAGE__->log(__PACKAGE__->logger);

# replace the warning handler with a call to our logger
$SIG{__WARN__} = sub { __PACKAGE__->log->warn(@_); }; ## no critic (RequireLocalizedPunctuationVars)

__PACKAGE__->log->info('Starting Venn...');

__PACKAGE__->setup();

1;
