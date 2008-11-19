#!perl -T

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Deep;
use Data::Dumper;
use lib 't/tlib';

eval { require MyTestServer; };
plan skip_all => "Pause/Resume tests require the AnyEvent::HTTP module: $@"
  if $@;

plan tests => 32;

my ($pid, $port) = MyTestServer->start_server(undef, keep_alive_timeout => 1, sub {
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
  elsif ($url eq '/stats') {
    $res->body(Dumper($srv->stats));
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
    $active--;
    
    is(
      $data, "Slept for $sleep_for",
      "Request sleep_for $sleep_for completed"
    );
    ok(time()-$now-1 <= $sleep_for, 'Timming ok');
    
    return if $active; 
    
    # Collect and check stats
    AnyEvent::HTTP::http_get("http://127.0.0.1:$port/stats", sub {
      my ($stats) = @_;
      
      # untaint, quick and very very dirty
      ($stats) = $stats =~ m/(.+)/sm;
      
      $stats = eval "my $stats";
      ok($stats);
      ok(scalar(%{$stats}));
      is($stats->{conn_failed}, 0);
      is($stats->{conn_success}, 2+$conns);
      is($stats->{tx_started}, 2+$conns);
      ok($stats->{timeout_ign});
      ok($stats->{reads});
      ok($stats->{writes});
      ok($stats->{reads_with_content});
            
      $stop->send
    });
  });
}

diag('Requests sent, waiting for replies');
$stop->recv;

MyTestServer->stop_server($pid);
