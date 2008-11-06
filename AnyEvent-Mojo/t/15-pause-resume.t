#!perl -T

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Deep;
use lib 't/tlib';

eval { require MyTestServer; };
plan skip_all => "Pause/Resume tests require the AnyEvent::HTTP module: $@"
  if $@;

plan tests => 23;

my ($pid, $port) = MyTestServer->start_server;

ok($port, "Server is up at $port, pid $pid");

my $stop = AnyEvent->condvar;


# It's my server, I'm evil
my $conns = 10;
{
  no warnings;
  $AnyEvent::HTTP::MAX_PER_HOST = $conns;
}

my $now = time;
my $count;
my $active = 0;
while ($count++ < $conns) {
  my $sleep_for = 11 - $count;
  $active++;   
  AnyEvent::HTTP::http_get("http://127.0.0.1:$port/$sleep_for", sub {
    my ($data) = @_;
    
    is(
      $data, "Slept for $sleep_for",
      "Request sleep_for $sleep_for completed"
    );
    ok(time()-$now-1 <= $sleep_for, 'Timming ok');
    
    $stop->send if --$active == 0; 
  });
}

diag('Requests sent, waiting for replies');
$stop->recv;

MyTestServer->stop_server($pid);


1;