#!perl

use v5.14;
use warnings;

use FindBin ();
use lib "$FindBin::Bin/../../lib";

use Venn::Dependencies;

use Perl::Critic::Utils;

use Test::Perl::Critic;
use Test::Builder;

#use Test::Most tests => 1;

my $TEST = Test::Builder->new();

# skip tests with NO_CRITIC=1
if ($ENV{NO_CRITIC}) {
    $TEST->plan( tests => 1 );
    $TEST->ok(1, "Skipping Perl::Critic tests");
}
else {
    my $project_root = "$FindBin::Bin/../..";

    my $rcfile = File::Spec->catfile( $project_root, 't', 'hygiene', 'perlcriticrc' );
    Test::Perl::Critic->import( -profile => $rcfile );

    require File::Spec;
    my $user = getlogin() || getpwuid($<) || $ENV{USER};
    my $cache_path = File::Spec->catdir(File::Spec->tmpdir, "venn-core-perlcritic-cache-$user");
    if (!-d $cache_path) {
       mkdir $cache_path, oct 700;
    }
    require PPI::Cache;
    PPI::Cache->import(path => $cache_path);

    if (defined $ENV{PERLCRITIC_ONLY}) {
        critic_ok($project_root . "/" . $ENV{PERLCRITIC_ONLY});
    }
    else {
        all_critic_ok_without_node("$project_root/lib");
    }
}

sub all_critic_ok_without_node {

    my @dirs = @_;
    if (not @dirs) {
        @dirs = _starting_points();
    }

    my @files = all_code_files_without_node( @dirs );
    $TEST->plan( tests => scalar @files );

    my $okays = grep { critic_ok($_) } @files;
    return $okays == @files;
}

sub all_code_files_without_node {

    my @dirs = @_;
    if (not @dirs) {
        @dirs = _starting_points();
    }

    return all_perl_files_without_node(@dirs);
}

sub all_perl_files_without_node {

    # Recursively searches a list of directories and returns the paths
    # to files that seem to be Perl source code.  This subroutine was
    # poached from Test::Perl::Critic.

    my %SKIP_DIR = map { $_ => 1 } qw( CVS RCS .svn _darcs {arch} .bzr .cdv .git .hg .pc _build blib node_modules Build );

    my @queue      = @_;
    my @code_files = ();

    while (@queue) {
        my $file = shift @queue;
        if ( -d $file ) {
            opendir my ($dh), $file or next;
            my @newfiles = sort readdir $dh;
            closedir $dh;

            @newfiles = File::Spec->no_upwards(@newfiles);
            @newfiles = grep { not $SKIP_DIR{$_} } @newfiles;
            push @queue, map { File::Spec->catfile($file, $_) } @newfiles;
        }

        if ( (-f $file) && ! Perl::Critic::Utils::_is_backup($file) && Perl::Critic::Utils::_is_perl($file) ) {
            push @code_files, $file;
        }
    }
    return @code_files;
}
