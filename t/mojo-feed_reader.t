#!/usr/bin/env perl
use Mojo::Base -strict;

use Mojo::IOLoop;
use Mojolicious::Lite;
use Test::More tests => 14;

use Mojo::FeedReader;

# Silence
app->log->level('fatal');

get '/hello' => sub { $_[0]->render(text => 'Hello there!') };

get '/rss' => sub {
  my $c = shift;
  $c->render(format => 'xml');
};

get '/atom' => sub {
  my $c = shift;
  $c->render(format => 'xml',);
};

my $reader = Mojo::FeedReader->new('/hello');
is($reader->url, '/hello', 'url as argument');

my ($res, $data);

$reader = Mojo::FeedReader->new('/not-found');
$reader->on(error => sub { $res = $_[1] });
$reader = undef;
Mojo::IOLoop->timer(0.25 => sub { Mojo::IOLoop->stop() });
Mojo::IOLoop->start();
is($res, undef, 'object instance destroy');

# data (atom)
$reader = Mojo::FeedReader->new(url => '/atom?from=10', interval => 0.25);
$reader->on(
  fetch => sub {
    $res = $_[1];
    Mojo::IOLoop->stop();
  }
);

Mojo::IOLoop->start();
$data = [map { _item_atom($_) } (reverse 10 .. 14)];
is_deeply($res, $data, 'fetch initial data (atom)');

$reader->url('/atom?from=12');
Mojo::IOLoop->start();
$data = [map { _item_atom($_) } (16, 15)];
is_deeply($res, $data, 'fetch new entries, first (atom)');

$reader->url('/atom?from=15');
Mojo::IOLoop->start();
$data = [map { _item_atom($_) } (19, 18, 17)];
is_deeply($res, $data, 'fetch new entries, second (atom)');

# data (rss)
$reader = Mojo::FeedReader->new(url => '/rss?from=10', interval => 0.25);
$reader->on(
  fetch => sub {
    $res = $_[1];
    Mojo::IOLoop->stop();
  }
);

Mojo::IOLoop->start();
$data = [map { _item_rss($_) } (reverse 10 .. 14)];
is_deeply($res, $data, 'fetch initial data (rss)');

$reader->url('/rss?from=12');
Mojo::IOLoop->start();
$data = [map { _item_rss($_) } (16, 15)];
is_deeply($res, $data, 'fetch new entries, first (rss)');

$reader->url('/rss?from=15');
Mojo::IOLoop->start();
$data = [map { _item_rss($_) } (19, 18, 17)];
is_deeply($res, $data, 'fetch new entries, second (rss)');

# isa
my ($isa_res, $isa_feed) = @_;
$reader = Mojo::FeedReader->new(url => '/rss?from=10', interval => 0.25);
$reader->on(
  fetch => sub {
    (undef, $isa_res, $isa_feed) = @_;
    Mojo::IOLoop->stop();
  }
);

Mojo::IOLoop->start();
isa_ok($isa_res,  'Mojo::Collection', 'response');
isa_ok($isa_feed, 'Mojo::DOM',        'feed');

# error
my $err;
$res = 'fetch-not-called';
$reader = Mojo::FeedReader->new(url => '/not-found', interval => 0.25);
$reader->on(fetch => sub { $res = $_[1] });
$reader->on(
  error => sub {
    $err = $_[1];
    Mojo::IOLoop->stop();
  }
);

Mojo::IOLoop->start();
is($err, 'Not Found',        'error text');
is($res, 'fetch-not-called', 'result on error');

# interval
my ($start_time, $end_time, $i);
$i = 2;
$reader = Mojo::FeedReader->new(url => '/rss', interval => 1);
$reader->on(
  fetch => sub {
    push @$end_time, time;
    Mojo::IOLoop->stop() unless --$i;
  }
);

$start_time = time;
Mojo::IOLoop->start();
is_deeply([$start_time, $start_time + 1], $end_time, 'interval');

# ttl
$end_time = [];
$i        = 2;
$reader   = Mojo::FeedReader->new(url => '/rss?ttl=0.016666666', interval => 3);
$reader->on(
  fetch => sub {
    push @$end_time, time;
    Mojo::IOLoop->stop() unless --$i;
  }
);

$start_time = time;
Mojo::IOLoop->start();
is_deeply([$start_time, $start_time + 1], $end_time, 'ttl from feed');

done_testing();

sub _item_atom {
  {
    description => "Item \"$_[0]\".",
    id          => "it$_[0]",
    link        => "/link/$_[0]",
    title       => "$_[0]",
    updated     => '2020-01-12T00:16:24Z',
  };
}

sub _item_rss {
  {description => "Item \"$_[0]\".", link => "/link/$_[0]", title => "$_[0]",};
}

__DATA__

@@ rss.xml.ep
% layout 'feed';
<rss version="2.0">
<channel>
  <title>Hello from Mojo.</title>
  <link>http://mojolicio.us</link>
  <description>web development can be fun again.</description>
  % my $ttl = $c->param('ttl');
  <%== $ttl ? "<ttl>$ttl</ttl>" : '' %>
  % my $i = ($c->param('from') || time) + 4;
  % for (0..4) {
      <item>
        <title><%= $i %></title>
        <link><%= "/link/$i" %></link>
        <description>Item "<%= $i %>".</description>
      </item>
  % $i--;
  % }
</channel>
</rss>

@@ atom.xml.ep
% layout 'feed';
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>urn:uuid:60a76c80-d399-11d9-b93C-0003939e0af6</id>
  <title>Hello from Mojo.</title>
  <link>http://mojolicio.us</link>
  <description>web development can be fun again.</description>
  <updated>2020-01-12T00:16:24Z</updated>
  % my $i = ($c->param('from') || time) + 4;
  % for (0..4) {
      <entry>
        <id><%= "it$i" %></id>
        <title><%= $i %></title>
        <updated>2020-01-12T00:16:24Z</updated>
        <link href="<%= "/link/$i" %>" />
        <description>Item "<%= $i %>".</description>
      </entry>
  % $i--;
  % }
</feed>

@@ layouts/feed.xml.ep
<?xml version="1.0" encoding="UTF-8"?>
<%== content %>
