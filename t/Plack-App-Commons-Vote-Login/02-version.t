use strict;
use warnings;

use Plack::App::Commons::Vote::Login;
use Test::More 'tests' => 2;
use Test::NoWarnings;

# Test.
is($Plack::App::Commons::Vote::Login::VERSION, 0.01, 'Version.');
