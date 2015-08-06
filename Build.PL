package VennBuildPL;

use strict;
use warnings;
use Module::Build;

use lib qw(lib);
use Venn::Dependencies;
BEGIN { eval qq{ use Venn::LocalBuild; }; }

my $fake_builder = Module::Build->new(module_name => 'Venn');
my @actions = $fake_builder->known_actions;
my @code;
for my $action (@actions) {
    push @code, sprintf('sub ACTION_%s { eval qq{ use Venn::LocalBuild; }; $_[0]->SUPER::ACTION_%s }',
                        $action, $action);
}

my $class = Module::Build->subclass(
    class => 'Module::Build::Venn',
    code => join("\n", @code),
);

my $builder = $class->new(
    module_name         => 'Venn',
    license             => 'perl',
    dist_author         => 'Venn Engineering <venn_dev@morganstanley.com>',
    dist_version_from   => 'lib/Venn.pm',
    build_requires => {
        'Test::More' => 0,
    },
    recursive_test_files => 1,
    add_to_cleanup      => [ 'Venn::*' ],
    create_makefile_pl => 'traditional',
    requires => \%Venn::Dependencies::DEPENDENCIES,
    cgi_files => {'fcgi-bin/venn_fastcgi.pl' => 'fcgi-bin/venn_fastcgi.pl'},
    root_files => {'root/index.html' => 'root/index.html',
                   'root/swagger/index.html' => 'root/swagger/index.html',
                   'root/swagger/api-docs.json' => 'root/swagger/api-docs.json',
                   'root/swagger/swagger-ui.min.js' => 'root/swagger/swagger-ui.min.js',
                   'root/swagger/o2c.html' => 'root/swagger/o2c.html',
                   'root/swagger/css/reset.css' => 'root/swagger/css/reset.css',
                   'root/swagger/css/screen.css' => 'root/swagger/css/screen.css',
                   'root/swagger/css/typography.css' => 'root/swagger/css/typography.css',
                   'root/swagger/lib/shred.bundle.js' => 'root/swagger/lib/shred.bundle.js',
                   'root/swagger/lib/shred/content.js' => 'root/swagger/lib/shred/content.js',
                   'root/swagger/lib/jquery-1.8.0.min.js' => 'root/swagger/lib/jquery-1.8.0.min.js',
                   'root/swagger/lib/jquery.slideto.min.js' => 'root/swagger/lib/jquery.slideto.min.js',
                   'root/swagger/lib/jquery.wiggle.min.js' => 'root/swagger/lib/jquery.wiggle.min.js',
                   'root/swagger/lib/jquery.ba-bbq.min.js' => 'root/swagger/lib/jquery.ba-bbq.min.js',
                   'root/swagger/lib/handlebars-2.0.0.js' => 'root/swagger/lib/handlebars-2.0.0.js',
                   'root/swagger/lib/underscore-min.js' => 'root/swagger/lib/underscore-min.js',
                   'root/swagger/lib/backbone-min.js' => 'root/swagger/lib/backbone-min.js',
                   'root/swagger/lib/swagger-client.js' => 'root/swagger/lib/swagger-client.js',
                   'root/swagger/lib/highlight.7.3.pack.js' => 'root/swagger/lib/highlight.7.3.pack.js',
                   'root/swagger/lib/marked.js' => 'root/swagger/lib/marked.js',
                   'root/swagger/fonts/droid-sans-v6-latin-700.eot' => 'root/swagger/fonts/droid-sans-v6-latin-700.eot',
                   'root/swagger/fonts/droid-sans-v6-latin-700.svg' => 'root/swagger/fonts/droid-sans-v6-latin-700.svg',
                   'root/swagger/fonts/droid-sans-v6-latin-700.ttf' => 'root/swagger/fonts/droid-sans-v6-latin-700.ttf',
                   'root/swagger/fonts/droid-sans-v6-latin-700.woff' => 'root/swagger/fonts/droid-sans-v6-latin-700.woff',
                   'root/swagger/fonts/droid-sans-v6-latin-700.woff2' => 'root/swagger/fonts/droid-sans-v6-latin-700.woff2',
                   'root/swagger/fonts/droid-sans-v6-latin-regular.eot' => 'root/swagger/fonts/droid-sans-v6-latin-regular.eot',
                   'root/swagger/fonts/droid-sans-v6-latin-regular.svg' => 'root/swagger/fonts/droid-sans-v6-latin-regular.svg',
                   'root/swagger/fonts/droid-sans-v6-latin-regular.ttf' => 'root/swagger/fonts/droid-sans-v6-latin-regular.ttf',
                   'root/swagger/fonts/droid-sans-v6-latin-regular.woff' => 'root/swagger/fonts/droid-sans-v6-latin-regular.woff',
                   'root/swagger/fonts/droid-sans-v6-latin-regular.woff2' => 'root/swagger/fonts/droid-sans-v6-latin-regular.woff2',
                   'root/swagger/images/explorer_icons.png' => 'root/swagger/images/explorer_icons.png',
                   'root/swagger/images/logo_small.png' => 'root/swagger/images/logo_small.png',
                   'root/swagger/images/throbber.gif' => 'root/swagger/images/throbber.gif',
               },
    script_files => {
        'script/testserver.pl' => 'script/testserver.pl',
        'script/venn_server.pl' => 'script/venn_server.pl',
    },
);
$builder->add_build_element('cgi');
$builder->add_build_element('root');
$builder->add_build_element('script');

$builder->create_build_script();
