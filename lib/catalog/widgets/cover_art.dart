import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/spotify_colors.dart';

/// Square artwork for a catalog item or a track: the real cover image when there
/// is one, over a tinted gradient that stands in for it.
///
/// The gradient is painted *underneath* the image rather than swapped out for
/// it, which is what keeps this widget stateless: there is no
/// loading/loaded/failed machine to run, because the placeholder is simply never
/// removed. A cover still downloading, one that 404s, and an item with no
/// artwork at all are all the same case -- the gradient shows through.
///
/// Sizes itself to its parent (every caller already wraps its cover in a
/// SizedBox or an AspectRatio) and decodes the bitmap at the size it will
/// actually be painted at.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.urls = const [],
    this.color,
    this.borderRadius = 8,
    this.iconSize = 40,
  });

  /// Interchangeable sources for the same image, best first, or empty for
  /// something with no artwork.
  ///
  /// More than one because a catalog served from a network of independent nodes
  /// hands out several hosts for the same bytes, and individual nodes go down --
  /// see [CatalogItem.coverUrls]. A caller with a single url passes a
  /// one-element list and gets the old behaviour exactly.
  final List<String> urls;

  /// ARGB tint for the placeholder gradient. Null gets a neutral dark one --
  /// what the player screens use, since a track carries no colour of its own.
  final int? color;

  final double borderRadius;

  /// Size of the music-note glyph on the placeholder, scaled to the cover.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // Blanks dropped here rather than guarded against downstream, so the state
    // below can treat the list as "things worth fetching" and index it freely.
    final sources = [
      for (final url in urls)
        if (url.isNotEmpty) url,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        // Hands our own constraints to both children, so the image and the
        // gradient behind it are always exactly the same square.
        fit: StackFit.passthrough,
        children: [
          _Placeholder(color: color, iconSize: iconSize),
          if (sources.isNotEmpty) _Cover(urls: sources),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.color, required this.iconSize});

  final int? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tint = color == null ? SpotifyColors.surfaceBright : Color(color!);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, Color.lerp(tint, Colors.black, 0.55)!],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note, color: Colors.white70, size: iconSize),
      ),
    );
  }
}

class _Cover extends StatefulWidget {
  const _Cover({required this.urls});

  /// At least one, none of them empty.
  final List<String> urls;

  @override
  State<_Cover> createState() => _CoverState();
}

/// Fetches [_Cover.urls] in order, moving to the next one the moment the current
/// one fails or stalls, and once they are exhausted going round again on a
/// growing delay.
///
/// The order matters more than it looks. Waiting *before* asking again only
/// makes sense when the plan is to ask the same host, and the two reasons a
/// cover fails want opposite treatment:
///
///  * The host is down. Measured on Audius, this is per-node and sticky -- a
///    dead node answered 502 five times running, for its own content and for
///    content it had never seen. No delay will fix that; another host will, at
///    once. So the first pass through the list waits for nothing.
///  * The network is down, or every host refused a burst at the same time
///    (Home asks for a dozen covers in one go, which is what a rate limiter is
///    built to refuse). Here a different host is no better, and spacing the
///    attempts out is the whole remedy. So once the list is spent, the delays
///    start.
class _CoverState extends State<_Cover> {
  /// How long to wait before each retry *after* every host has had a turn.
  /// The length of this list is the extra budget beyond that first pass.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 300),
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// How long an attempt may go without producing a frame before it is treated
  /// as lost. This is not belt-and-braces on top of [errorBuilder]: on the web
  /// it is the ONLY thing that fires. A network image that fails there never
  /// reports an error at all -- measured with a raw Image.network against a url
  /// answering 403, under every WebHtmlElementStrategy: all three sit in
  /// loadingBuilder for ever and errorBuilder is never called. So the widget
  /// cannot wait to be told a cover failed; it has to notice.
  static const Duration _stall = Duration(seconds: 6);

  /// Which attempt is in the tree. It is also the [Image]'s key: a *new* key is
  /// what makes Flutter build a fresh image state, and only a fresh state
  /// re-resolves the provider. Calling setState alone would change nothing,
  /// because the provider compares equal to the one that just failed.
  int _attempt = 0;

  /// The host this attempt is aimed at. Cycles, so the delayed retries after the
  /// first pass start again from the best source rather than sticking on the
  /// last one, which is only where the walk happened to stop.
  String get _url => widget.urls[_attempt % widget.urls.length];

  /// How long to wait before attempt [n], or null when the budget is spent.
  ///
  /// Zero while sources remain untried: nothing has been learned about a host
  /// that has not been asked, so there is nothing to back off from.
  Duration? _delayBefore(int n) {
    if (n < widget.urls.length) return Duration.zero;
    final index = n - widget.urls.length;
    return index < _backoff.length ? _backoff[index] : null;
  }

  Timer? _scheduled;
  Timer? _watchdog;

  /// The provider currently in the tree, kept so a retry can evict it.
  /// Rebuilding with the same url alone would change nothing: ImageCache is
  /// keyed by provider, so a re-resolve JOINS the in-flight load rather than
  /// starting a new one -- which for a request that hangs means waiting on the
  /// very thing that already failed to arrive.
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _armWatchdog();
  }

  /// Starts the clock on the attempt now in the tree. Cancelled by the first
  /// frame -- see frameBuilder.
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_stall, () {
      if (mounted) _scheduleRetry();
    });
  }

  @override
  void didUpdateWidget(_Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // By value, not by identity: the parent filters blanks out of its `urls` on
    // every build, so the list arriving here is a fresh object each time even
    // when it holds the same strings. Comparing with != would see a different
    // cover on every rebuild and restart the walk for ever.
    if (!listEquals(widget.urls, oldWidget.urls)) {
      // A different cover entirely -- the old one's budget does not apply.
      _scheduled?.cancel();
      _scheduled = null;
      _attempt = 0;
      _armWatchdog();
    }
  }

  @override
  void dispose() {
    _scheduled?.cancel();
    _watchdog?.cancel();
    super.dispose();
  }

  /// Queues the next attempt, unless the budget is spent or one is already
  /// queued (errorBuilder runs on every rebuild, not just the failure).
  void _scheduleRetry() {
    if (_scheduled != null) return;
    final delay = _delayBefore(_attempt + 1);
    if (delay == null) return;
    _scheduled = Timer(delay, () async {
      if (!mounted) return;
      // Even when the next attempt is a different host, and so a different
      // provider: this one has to go, or cycling back round to it later would
      // be answered out of the image cache with the failure it is holding.
      await _provider?.evict();
      if (!mounted) return;
      setState(() {
        _scheduled = null;
        _attempt++;
      });
      _armWatchdog();
    });
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder rather than a size parameter: the widget then decodes
    // correctly wherever it is put, including the full player's cover, which has
    // no fixed size at all. Without cacheWidth a 600px cover in a 48px list tile
    // would hold well over a hundred times the pixels it can possibly show.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final decodeWidth = width.isFinite && width > 0
            ? (width * MediaQuery.devicePixelRatioOf(context)).round()
            : null;

        // Spelled out rather than Image.network, which builds exactly this and
        // then keeps it to itself -- and a retry has to be able to evict it.
        _provider = ResizeImage.resizeIfNeeded(
          decodeWidth,
          null,
          NetworkImage(
            _url,
            // Web only. There, Flutter's default is
            // WebHtmlElementStrategy.never: a NetworkImage is fetched as BYTES
            // over XHR so the engine can decode it into the canvas, which needs
            // the host's CORS blessing and dies on any non-2xx. `fallback` keeps
            // that fast path and adds a second go through a plain <img>, which
            // the same-origin policy does not gate at all -- the difference
            // between a cover and a blank square on a CDN that will serve an
            // image but not bless a cross-origin fetch. It renders as a platform
            // view, so it costs a little performance and ignores image
            // filtering: fine for a path only taken when the proper one failed.
            // Ignored on every non-web platform.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
          ),
        );

        return Image(
          image: _provider!,
          // Not decoration: a new key is what builds a fresh image state, and
          // only a fresh state re-resolves after the eviction above.
          key: ValueKey(_attempt),
          fit: BoxFit.cover,
          // Squeezing a 600px photo into a 48px tile aliases visibly at the
          // default (low) quality.
          filterQuality: FilterQuality.medium,
          // Every cover has its title and artist rendered right beside it, so
          // announcing the artwork too would only repeat them.
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              // It arrived: stop watching for a stall.
              _watchdog?.cancel();
              _watchdog = null;
            }
            // Already in the image cache (scrolling back to a row, reopening the
            // player): show it at once, or it would flicker through the fade.
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
          // Draw nothing and let the placeholder stand -- deliberately silent,
          // a missing cover is not worth an error icon -- but queue the next
          // attempt. Without this a single refused request (a dead content node,
          // a rate limit, a lost packet on mobile, a captive portal) blanks that
          // cover for the rest of the session, because nothing else ever
          // re-resolves it.
          errorBuilder: (context, error, stackTrace) {
            _scheduleRetry();
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
