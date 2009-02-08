#!perl -T

use strict;
use warnings;
use Test::More tests => 83;
use Test::Exception;
use Test::Deep;
use AnyEvent::Mojo;
use lib 't/tlib';
use MyTestServer;

my ($pid, $port) = MyTestServer->start_server(undef, keep_alive_timeout => 1, sub {
  my ($srv, $tx) = @_;
  my $conn = $tx->connection;
  my $res  = $tx->res;
  my $url  = $tx->req->url;
  
  if ($url->path ne '/') {
    $res->code(404);

    my $body = 'These are not the droids you are looking for...';
    $res->headers->content_length(length($body));
    $res->body($body);
    return;
  }
  
  $res->code(200);
  $res->headers->content_type('text/plain');
  my $body = 
     "pid: $$\nreq_per_conn: " . $conn->request_count
     . "\ntotal_req: "         . $conn->server->request_count;
  
  $res->body($body);
  
  return;
});

ok($port, "Server is up at $port, pid $pid");

# 10 keep-alive requests
# Start server already did one connection
my $count;
my $total;
my $delta = 1;

my $client = mojo_client();

my $url = "http://127.0.0.1:$port/";
my $cb;

$cb = sub {
  my ($tx) = @_;
  $count++;

print STDERR "+++ GOT TX state is ".$tx->state."\n";  
  is($tx->res->code, 200);
  my $body = $tx->res->body;
  
  like($body, qr/pid: $pid/);
  like($body, qr/req_per_conn: $count/);
  $total = $count + $delta;
  print STDERR "CHECK $count $delta = $total\n";
  like($body, qr/total_req: $total/);
  
  if ($count < 10) {
    my $t; $t = AnyEvent->timer(
      after => .1,
      cb    => sub {
        mojo_get($url, $cb);
        undef $t;
      }
    );
  }
  else {
    $client->stop;
  }
};

mojo_get($url, $cb);
$client->run;


# Max keep alive timeout is 1
my $t; $t = AnyEvent->timer(
  after => 5,
  cb    => sub {
    $client->stop;
    undef $t;
  },
);
$client->run;


# another 10 keep-alive requests
$count = 0;
$delta = 11;

mojo_get($url, $cb);
$client->run;

MyTestServer->stop_server($pid);
