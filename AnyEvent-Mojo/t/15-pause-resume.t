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

my ($pid, $port) = MyTestServer->start_server(undef, keep_alive_timeout => 30, sub {
  my ($srv, $tx) = @_;
  my $conn = $tx->connection;
  my $res  = $tx->res;
  my $url  = $tx->req->url;
  my ($delay) = $url =~ m{/([\d.]+)};
  
  $res->code(200);
  $res->headers->content_type('text/plain');

  if ($delay) {
    my $body = "Slept for $delay";
    $res->body($body);

    my $resume_cb = $conn->pause;
    my $t; $t = AnyEvent->timer( after => $delay, cb => sub {
      # Resume the transaction
      $resume_cb->();

      # Timer no longer needed
      undef $t;
    });
  }
  else {
    $res->body('Hi!');
  }
      
  return;
});

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
