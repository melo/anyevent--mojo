#!perl -T

use strict;
use warnings;
use Test::More tests => 7;
use Test::Exception;
use AnyEvent::HTTP;

BEGIN {
	use_ok( 'AnyEvent::Mojo' );
}

my $server = AnyEvent::Mojo->new;
isa_ok($server, 'Mojo::Server');
is($server->port, 3000, 'Expected default port');

my $new_port = 4000 + $$ % 10000;
$server->port($new_port);
is($server->port, $new_port, 'Port change sucessful');

lives_ok sub { $server->listen }, 'Server started ok';

# Trigger to stop the tests
my $stop = AnyEvent->condvar;

# GET the server
my $timer; $timer = AnyEvent->timer( after => .5, cb => sub {
  http_get("http://0.0.0.0:$new_port/", sub {
    my ($content) = @_;
    
    ok($content, 'Got some content back');
    like(
      $content,
      qr/Congratulations, your Mojo is working!/,
      'Content matches expected result'
    );
    
    $stop->send;
  });
});

# Run the tests
$stop->recv;
