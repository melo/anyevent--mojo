#!perl

use strict;
use Test::More;

use_ok( 'AnyEvent::Mojo::Server::Connection' );
use_ok( 'AnyEvent::Mojo::Server' );
use_ok( 'AnyEvent::Mojo' );

diag( "Testing AnyEvent::Mojo $AnyEvent::Mojo::VERSION, Perl $], $^X" );

done_testing;