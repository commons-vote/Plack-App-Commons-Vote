use strict;
use warnings;

use Plack::App::Commons::Voting;
use Test::More 'tests' => 2;
use Test::NoWarnings;

# Test.
is($Plack::App::Commons::Voting::VERSION, 0.01, 'Version.');
