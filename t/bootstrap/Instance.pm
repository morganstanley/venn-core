package t::bootstrap::Instance;

use Moose;
use Time::HiRes 'sleep';
use POSIX 'SIGTERM';
use Net::EmptyPort qw(empty_port wait_port);
use FindBin qw($Bin);

BEGIN {
    # ensure this instance runs an in-memory server
    $ENV{VENN_ENV} = 'sqlite';
    $ENV{VENN_IN_MEMORY} = 1;
    $ENV{no_proxy} = "localhost";
}

has executable => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    default => "$Bin/../../script/venn_server.pl",
);

has parameters => (
    is => 'ro',
    isa => 'ArrayRef',
    lazy => 1,
    builder => '_build_parameters',
);

sub _build_parameters {
    my ($self) = @_;

    return [
        '-p', $self->port,
    ];
}

has bind_ip => (
    is => 'ro',
    isa => 'Str',
    default => '127.0.0.1',
);

has port => (
    is => 'ro',
    isa => 'Int',
    default => sub { empty_port() },
);

has 'pid' => (
    is => 'rw',
    isa => 'Int',
    lazy => 1,
    default => undef,
    init_arg => undef,
);

sub BUILD {
    my $self = shift;
    my $params = shift // {};

    $self->{$_} = $params->{$_} for (keys %$params);

    if ($self->{set_env}) {
        $ENV{VENN_SERVER} = 'http://localhost:'.$self->port;
    }
    
    die sprintf "Executable %s not found", $self->executable unless -x $self->executable;
    my $pid = fork;
    die "fork failed:$!" unless defined $pid;

    if ($pid == 0) {
        exec $self->executable, @{$self->parameters};
    }

    until ( wait_port($self->port, 1) ) { sleep 1; }
    $self->pid($pid);

    return $self;
}

sub stop {
    my ($self, $sig) = @_;
    return unless $self->pid;

    $sig ||= SIGTERM;
    kill $sig, $self->pid;

    sleep 0.1;
    waitpid $self->pid, 0;

    return 1;
}

sub DEMOLISH {
    my $self = shift;

    $self->stop;

    return;
}

__PACKAGE__->meta->make_immutable();

