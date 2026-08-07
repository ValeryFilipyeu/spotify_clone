import 'dart:async';

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
    this.url,
    this.color,
    this.borderRadius = 8,
    this.iconSize = 40,
  });

  /// The remote cover, or null for something with no artwork.
  final String? url;

  /// ARGB tint for the placeholder gradient. Null gets a neutral dark one --
  /// what the player screens use, since a track carries no colour of its own.
  final int? color;

  final double borderRadius;

  /// Size of the music-note glyph on the placeholder, scaled to the cover.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        // Hands our own constraints to both children, so the image and the
        // gradient behind it are always exactly the same square.
        fit: StackFit.passthrough,
        children: [
          _Placeholder(color: color, iconSize: iconSize),
          if (url != null && url.isNotEmpty) _Cover(url: url),
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
  const _Cover({required this.url});

  final String url;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> {
  /// How long to wait before each retry. The length of this list IS the retry
  /// budget, and the delays grow so a host that is refusing everyone for a
  /// moment is not hammered: covers load in a burst (Home asks for a dozen at
  /// once), and a burst is exactly what a rate limiter answers with a refusal.
  /// Spreading the retries out is what lets the burst drain.
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
    if (widget.url != oldWidget.url) {
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

  /// Queues another go at the same url, unless the budget is spent or one is
  /// already queued (errorBuilder runs on every rebuild, not just the failure).
  void _scheduleRetry() {
    if (_scheduled != null || _attempt >= _backoff.length) return;
    _scheduled = Timer(_backoff[_attempt], () async {
      if (!mounted) return;
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
            widget.url,
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
          // a missing cover is not worth an error icon -- but queue another go.
          // Without this a single refused request (a rate limit, a lost packet
          // on mobile, a captive portal) blanks that cover for the rest of the
          // session, because nothing else ever re-resolves it.
          errorBuilder: (context, error, stackTrace) {
            _scheduleRetry();
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
