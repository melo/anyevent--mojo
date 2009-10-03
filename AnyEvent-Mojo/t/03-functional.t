#!perl

use strict;
use warnings;
use Test::More;
use AnyEvent;
use AnyEvent::Mojo;

eval { require AnyEvent::HTTP; AnyEvent::HTTP->import };
plan skip_all => "Functional tests require the AnyEvent::HTTP module: $@"
  if $@;

my $port = 4000 + $$ % 10000;
my $server; $server = mojo_server(undef, $port, sub {
  my (undef, $tx) = @_;
  my $res = $tx->res;
  
  $res->code(200);
  $res->headers->content_type('text/plain');
  $res->body('Mary had a little lamb... but she was hungry... Lamb chops for dinner!');
  
  return;
});
ok($server);
is($server->host, '0.0.0.0');
is($server->port, $port);
is(ref($server->handler_cb), 'CODE');

my $t; $t = AnyEvent->timer( after => .5, cb => sub {
  http_get( "http://127.0.0.1:$port/", sub {
    my ($content) = @_;
    
    ok($content, 'got content back');
    like($content, qr/Lamb chops for dinner/, '... and it is the right content');
    
    $server->stop;
  });
});

$server->run;
pass("Server stoped properly");

## Test forced host
$server = mojo_server({
  host => '127.0.0.1',
  port => $port,
  handler_cb => sub {},
});
ok($server);
is($server->host, '127.0.0.1');
is($server->port, $port);
is(ref($server->handler_cb), 'CODE');

done_testing();
