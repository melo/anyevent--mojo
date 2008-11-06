#!perl -T

use strict;
use warnings;
use Test::More;
use Test::Exception;
use Test::Deep;
use Mojo::Client;
use lib 't/tlib';

eval { require MyTestServer; };
plan skip_all => "KeepAlive tests require the AnyEvent::HTTP module: $@"
  if $@;

plan tests => 83;

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
my $cln = Mojo::Client->new;

# Start server already did one connection
my $count;
my $total;
while ($count++ < 10) {
  my $tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/");
  
  $cln->process_all($tx);

  is($tx->res->code, 200);
  my $body = $tx->res->body;
  
  like($body, qr/pid: $pid/);
  like($body, qr/req_per_conn: $count/);
  $total = $count + 1;
  like($body, qr/total_req: $total/);
}

# Max keep alive timeout is 1
sleep(2);

# 10 keep-alive requests
$count = 0;
while ($count++ < 10) {
  my $tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/");
  
  $cln->process_all($tx);

  is($tx->res->code, 200);
  my $body = $tx->res->body;
  
  like($body, qr/pid: $pid/);
  like($body, qr/req_per_conn: $count/);
  
  my $t = $count + 11;
  like($body, qr/total_req: $t/);
}

MyTestServer->stop_server($pid);
