package Mojo::FeedReader;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::Collection;
use Mojo::DOM;
use Mojo::IOLoop;
use Mojo::UserAgent;
use Mojo::Util qw(encode sha1_sum);
use Scalar::Util qw(looks_like_number weaken);

has interval => 600;
has ioloop   => sub { Mojo::IOLoop->singleton() };
has info     => sub { {} };
has ua       => sub { Mojo::UserAgent->new()->max_redirects(2) };
has url      => '';

our $VERSION = '0.21';

sub DESTROY {
  Mojo::Util::_global_destruction()
    or ($_[0]->{_timer} && $_[0]->ioloop->remove($_[0]->{_timer}));
}

sub new {
  my $self = shift->SUPER::new(@_ == 1 && !ref $_[0] ? (url => $_[0]) : @_);

  $self->once(fetch => \&_prepare);

  # Don't want to access url attr until event loop start.
  my $wself = $self;
  weaken $wself;
  $self->ioloop->next_tick(sub { $wself && $wself->_fetch() });
  $self;
}

sub stop {
  $_[0]->ioloop->remove($_[0]->{_timer}) if @_ > 1 && $_[0]->{_timer};
  $_[0]->ioloop->stop();
}

sub wait {
  $_[0]->ioloop->start unless $_[0]->ioloop->is_running;
}

sub _fetch {
  my $self = shift;

  $self->ua->get(
    $self->url => sub {
      my ($ua, $tx) = @_;

      if (my $err = $tx->error) { return $self->emit(error => $err->{message}) }
      $self->_handle_entries(
        Mojo::DOM->new()->xml(1)->parse($tx->result->text));
    }
  );
}

sub _handle_entries {
  my ($self, $feed) = @_;

  my $cache       = $self->{_entries_cache} ||= {};
  my $new_entries = Mojo::Collection->new();
  my $now         = time;

  for my $dom_entry (@{$feed->find('channel > item, feed > entry')}) {
    my $entry = {map { $_->tag => $_->text } @{$dom_entry->children}};

    $entry->{link} = $dom_entry->at('link')->attr('href') || ''
      if exists $entry->{link} && !$entry->{link};

    my $hash = '';
    $hash .= $entry->{$_} // '' for qw(title link id);
    $hash = sha1_sum encode 'UTF-8', $hash;
    my $was_cached = delete $cache->{$hash};
    $cache->{$hash} = $now;
    next if $was_cached;

    push @$new_entries, $entry;
  }

  $cache->{$_} < $now && delete $cache->{$_} for keys %$cache;

  $self->emit('fetch', $new_entries, $feed) if @$new_entries;

  $self;
}

sub _prepare {
  my ($self, $entries, $feed) = @_;

  $feed->find('channel > *:not(item), feed > *:not(entry)')
    ->map(sub { $self->{info}{$_[0]->tag} = $_[0]->text });

  $self->interval($self->{info}{ttl} * 60)
    if looks_like_number $self->{info}{ttl};

  weaken $self;
  $self->{_timer}
    = Mojo::IOLoop->recurring($self->interval => sub { $self->_fetch() });

  $self;
}

1;

__END__

=encoding utf8

=head1 NAME

Mojo::FeedReader - minimalistic perl feed reader

=head1 SYNOPSIS

  use Mojo::FeedReader;

  my $reader = Mojo::FeedReader->new('http://example.com/rss');

  $reader->on(
    fetch => sub {
      my ($reader, $entries, $feed) = @_;
      say $entries->map(sub { $_->{title} })->join("\n");
    }
  );

  $reader->on(
    error => sub {
      my ($reader, $msg) = @_;
      warn "Oops! $msg";
    }
  );

  $reader->wait();

=head1 DESCRIPTION

Very minimalistic perl RSS/ATOM feed reader based on L<Mojo::UserAgent> and
L<Mojo::DOM>.

=head1 EVENTS

L<Mojo::FeedReader> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 error

  $reader->on(error => sub {
    my ($reader, $msg) = @_;
    ...
  });

Emitted on errors.

=head2 fetch

  $reader->on(fetch => sub {
    my ($reader, $entries, $feed) = @_;
    ...
  });

Emitted when new entries are available. Receives a L<Mojo::Collection> of hashrefs
with fetched entries and a L<Mojo::DOM> object with parsed feed.

=head1 ATTRIBUTES

=head2 interval
  
  my $interval = $reader->interval;
  $reader      = $reader->interval(900);

Interval between recurring requests in seconds. Defaults to C<ttl> value from
feed or C<600>.

=head2 ioloop

  my $loop = $reader->ioloop;
  $reader  = $reader->ioloop(Mojo::IOLoop->new);
 
Event loop object to control, defaults to the global L<Mojo::IOLoop> singleton.

=head2 info

  my $info = $reader->info;
  $reader  = $reader->info({title => 'Test feed'});

Hashref with a feed metadata. Holds various info fetched from the feed.

=head2 ua

  my $ua  = $reader->ua;
  $reader = $reader->ua(Mojo::UserAgent->new());

User agent object to use for requests. Defaults to a L<Mojo::UserAgent> with
max_redirects set to C<2>.

=head2 url

  my $url = $reader->url;
  $reader = $reader->url('http://another.example.com/rss');

URL of a feed to fetch.

=head1 METHODS

Some convenient shortcuts for controlling an event loop.

=head2 stop

  # stop an event loop
  $reader->stop();

  # stop an event loop and remove a recurring timer
  $reader->stop(1);

Stops an L</ioloop>.

If called with an argument, will remove a recurring fetch timer as well. It will
be impossible to restart again.

=head2 wait

  my $reader = Mojo::FeedReader->new('http://rss.me/')
    ->on(fetch => sub { ... });
  $reader->wait();

Starts an L</ioloop> unless it's already running.

=head1 COPYRIGHT AND LICENSE

Andre Parker <andreparker@gmail.com>, 2016, 2018.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
