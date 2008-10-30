#!perl -T

use strict;
use warnings;
use Test::More tests => 83;
use Test::Exception;
use Test::Deep;
use AnyEvent::Mojo;
use Mojo::Client;

my $port = 4000 + $$ % 10000;
my $pid = start_server($port);

ok($port, "Server is up at $port, pid $pid");

# 10 keep-alive requests
my $cln = Mojo::Client->new;

my $count;
while ($count++ < 10) {
  my $tx = Mojo::Transaction->new_get("http://127.0.0.1:$port/");
  
  $cln->process_all($tx);

  is($tx->res->code, 200);
  my $body = $tx->res->body;
  
  like($body, qr/pid: $pid/);
  like($body, qr/req_per_conn: $count/);
  like($body, qr/total_req: $count/);
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
  
  my $t = $count + 10;
  like($body, qr/total_req: $t/);
}

stop_server($pid);


##########################################
# Start an child process to run the server

sub start_server {
  my $port = shift;
  
  my $pid = fork();
  die "Could not fork: $!" unless defined $pid;
  if ($pid) {
    sleep(1); # wait for server to start
    return $pid;
  }

  # Child
  my $server = AnyEvent::Mojo->new;
  $server->keep_alive_timeout(1);
  $server->port($port)->handler_cb(sub {
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
  
  $server->run;
  exit(0);
}

sub stop_server {
  my $pid = shift;
  
  return unless $pid;
  
  is(kill(15, $pid), 1, "killed one"); # sigterm
  is(waitpid($pid, 0), $pid, "waipid ok");

  return;
}


1;