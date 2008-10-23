#!perl -T

use strict;
use warnings;
use Test::More tests => 12;
use Test::Exception;
use Test::Deep;
use AnyEvent::HTTP;
use IO::Socket qw( SOMAXCONN );

BEGIN {
	use_ok( 'AnyEvent::Mojo' );
}

my $server = MyTestServer->new;
isa_ok($server, 'Mojo::Server');
is($server->port, 3000, 'Expected default port');
is($server->listen_queue_size, SOMAXCONN, 'Expected default port');
ok(!defined($server->banner_called), 'Server not up yet');

my $new_port = 4000 + $$ % 10000;
$server->port($new_port);
is($server->port, $new_port, 'Port change sucessful');

lives_ok sub { $server->listen }, 'Server started ok';
cmp_deeply($server->banner_called, [ '0.0.0.0', $new_port ]);

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
    
    lives_ok sub { $server->stop };
  });
});

# Run the tests
$server->run;

lives_ok sub { $server->stop }, 'Second call to stop is harmless';


package MyTestServer;

use strict;
use warnings;
use base 'AnyEvent::Mojo';

BEGIN {
  __PACKAGE__->attr('banner_called');
}

sub startup_banner {
  my $self = shift;
  
  $self->banner_called($self->host, $self->port);
  return $self->SUPER::startup_banner(@_);
}

1;