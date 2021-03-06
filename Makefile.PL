use lib '.';
use strict;
use warnings;

use inc::Module::Install;

# Definition.
abstract 'Plack application for Wikimedia Commons voting.';
author 'Michal Josef Spacek <skim@cpan.org>';
author_requires 'English' => 0;
author_requires 'File::Object' => 0;
author_requires 'Test::More' => 0;
author_requires 'Test::NoWarnings' => 0;
author_requires 'Test::Pod' => 0;
author_requires 'Test::Pod::Coverage' => 0;
license 'bsd';
name 'Plack-App-Commons-Vote';
perl_version 5.008;
readme_from 'Vote.pm';
recursive_author_tests('xt');
requires 'English' => 0;
requires 'Error::Pure' => 0;
requires 'Plack::Component::Tags::HTML' => 0;
requires 'Tags::HTML::Vote::Commons' => 0;
resources 'bugtracker' => 'https://github.com/michal-josef-spacek/Plack-App-Commons-Vote';
resources 'homepage' => 'https://github.com/michal-josef-spacek/Plack-App-Commons-Vote';
resources 'repository' => 'git://github.com/michal-josef-spacek/Plack-App-Commong-Vote';
test_requires 'Error::Pure' => 0;
test_requires 'File::Object' => 0;
test_requires 'HTTP::Request' => 0;
test_requires 'Plack::Test' => 0;
test_requires 'Tags::Output::Indent' => 0;
test_requires 'Test::More' => 0;
test_requires 'Test::NoWarnings' => 0;
tests_recursive;
version '0.01';

# Run.
WriteAll();
