package Venn::Log::L4PWrapper;

=head1 NAME

Venn::Log::L4PWrapper - Wrapper for Log4perl

=head1 DESCRIPTION

Wraps Log4perl and provides convience methods for the level log methods.

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

use 5.010;
use Moose;

BEGIN {
    use Carp;
    use Log::Log4perl qw(:easy);
    my $log4perl_config = eval { Venn->config->{'log'}->{'log4perl_conf'} };
    if ($log4perl_config) {
        # `kill -HUP $pid` will reload the config
        Log::Log4perl->init_and_watch(Venn->config->{'log'}->{'log4perl_conf'}, 'HUP');
    }
    else {
        # by default, print out everything
        Log::Log4perl->easy_init($TRACE);
    }
};

has '_logger' => (
    is       => 'ro',
    isa      => 'Log::Log4perl::Logger',
    required => 1,
    handles  => [qw/ trace debug info warn error fatal logcarp logcluck logcroak logconfess /],
    documentation => '',
);

around BUILDARGS => sub {
    my ($orig, $self, $logger) = @_;

    return $self->$orig(_logger => $logger);
};

=head1 METHODS

See L<Log::Log4perl> for trace, debug, info, warn, error, and fatal methods.

=head2 new($logger)

Create a new Venn::LogWrapper to wrap Log::Log4perl::Logger $logger.

=head2 tracef($sprintf_format, @args)

=head2 debugf($sprintf_format, @args)

=head2 infof($sprintf_format, @args)

=head2 warnf($sprintf_format, @args)

=head2 errorf($sprintf_format, @args)

=head2 fatalf($sprintf_format, @args)

=head2 logcarpf($sprintf_format, @args)

=head2 logcluckf($sprintf_format, @args)

=head2 logcroakf($sprintf_format, @args)

=head2 logconfessf($sprintf_format, @args)

=cut

## no critic (RequireArgUnpacking)
sub tracef { return shift->_logger->trace(sprintf(shift, @_)); }
sub debugf { return shift->_logger->debug(sprintf(shift, @_)); }
sub infof { return shift->_logger->info(sprintf(shift, @_)); }
sub warnf { return shift->_logger->warn(sprintf(shift, @_)); }
sub errorf { return shift->_logger->error(sprintf(shift, @_)); }
sub fatalf { return shift->_logger->fatal(sprintf(shift, @_)); }
sub logcarpf { return shift->_logger->logcarp(sprintf(shift, @_)); }
sub logcluckf { return shift->_logger->logcluck(sprintf(shift, @_)); }
sub logcroakf { return shift->_logger->logcroak(sprintf(shift, @_)); }
sub logconfessf { return shift->_logger->logconfess(sprintf(shift, @_)); }
## use critic

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
