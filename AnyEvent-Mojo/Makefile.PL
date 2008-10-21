use inc::Module::Install;

name     'AnyEvent-Mojo';
all_from 'lib/AnyEvent/Mojo.pm';
author   'Pedro Melo <melo@cpan.org>';

build_requires 'Test::More';

auto_install;

WriteAll;

