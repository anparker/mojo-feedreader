# Mojo::FeedReader

Very minimalistic RSS/ATOM feed reader based on [Mojo::UserAgent](https://metacpan.org/pod/Mojo::UserAgent) and
[Mojo::DOM](https://metacpan.org/pod/Mojo::DOM).

```perl
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

```

For more information and examples look up embedded documentation.
