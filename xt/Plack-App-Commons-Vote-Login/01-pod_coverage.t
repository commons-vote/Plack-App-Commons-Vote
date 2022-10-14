use strict;
use warnings;

use Test::NoWarnings;
use Test::Pod::Coverage 'tests' => 2;

# Test.
pod_coverage_ok('Plack::App::Commons::Vote::Login', 'Plack::App::Commons::Vote::Login is covered.');
