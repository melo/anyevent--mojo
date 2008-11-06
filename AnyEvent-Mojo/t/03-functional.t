#!perl

use strict;
use warnings;
use Test::More;
use AnyEvent;
use AnyEvent::Mojo;

eval { require AnyEvent::HTTP; AnyEvent::HTTP->import };
plan skip_all => "Functional tests require the AnyEvent::HTTP module: $@"
  if $@;

plan tests => 4;

my $port = 4000 + $$ % 10000;
my $server; $server = mojo_server(undef, $port, sub {
  my (undef, $tx) = @_;
  my $res = $tx->res;
  
  $res->code(200);
  $res->headers->content_type('text/plain');
  $res->body('Mary had a little lamb... but she was hundry... Lamb chops for dinner!');
  
  return;
});
ok($server);

my $t; $t = AnyEvent->timer( after => .5, cb => sub {
  http_get( "http://127.0.0.1:$port/", sub {
    my ($content) = @_;
    
    ok($content);
    like($content, qr/Lamb chops for dinner/);
    
    $server->stop;
  });
});

$server->run;

pass("Ended properly");
