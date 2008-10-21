#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'AnyEvent::Mojo' );
}

diag( "Testing AnyEvent::Mojo $AnyEvent::Mojo::VERSION, Perl $], $^X" );
