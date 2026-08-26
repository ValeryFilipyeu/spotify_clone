import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/spotify_colors.dart';
import '../images/cover_image_provider.dart';
import '../images/cover_image_scope.dart';

/// Square artwork: the real cover over a tinted gradient standing in for it.
///
/// The gradient is painted *underneath* rather than swapped out, which is what
/// keeps this stateless -- still downloading, 404, and no artwork at all are one
/// case, and the placeholder simply shows through.
///
/// Sizes itself to its parent and decodes at the size it will be painted.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.urls = const [],
    this.color,
    this.borderRadius = 8,
    this.iconSize = 40,
  });

  /// Interchangeable sources for the same image, best first, or empty for
  /// something with no artwork. Several because Audius' nodes go down
  /// individually -- see [CatalogItem.coverUrls].
  final List<String> urls;

  /// ARGB tint for the placeholder gradient; null gets a neutral dark one.
  final int? color;

  final double borderRadius;

  /// Size of the placeholder's music-note glyph.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // Dropped here so the state below can index the list freely.
    final sources = [
      for (final url in urls)
        if (url.isNotEmpty) url,
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        // Both children get our constraints, so they are the same square.
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

/// Walks [_Cover.urls] in order, moving on the moment one fails or stalls, then
/// cycles again on a growing delay.
///
/// The order matters: a delay only helps if the plan is to ask the same host, and
/// the two failure modes want opposite treatment. A dead node is sticky (measured:
/// 502 five times running, even for content it had never seen) so the first pass
/// waits for nothing. A dead network or a rate limiter refusing Home's dozen
/// covers at once needs spacing, so the delays start once the list is spent.
class _CoverState extends State<_Cover> {
  /// Delays for the retries after every host has had a turn. Its length is the
  /// extra budget beyond that first pass.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 300),
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// How long an attempt may go without a frame before it counts as lost.
  ///
  /// Not belt-and-braces on top of `errorBuilder`: on the web it is the only
  /// thing that fires. Measured against a url answering 403 under every
  /// WebHtmlElementStrategy, all three sit in `loadingBuilder` for ever.
  static const Duration _stall = Duration(seconds: 6);

  /// Which attempt is in the tree, and the [Image]'s key: only a fresh state
  /// re-resolves the provider, and setState alone would not give one, since the
  /// provider compares equal to the one that just failed.
  int _attempt = 0;

  /// The host this attempt is aimed at. Cycles, so delayed retries start again
  /// from the best source rather than wherever the walk stopped.
  String get _url => widget.urls[_attempt % widget.urls.length];

  /// How long to wait before attempt [n], or null when the budget is spent. Zero
  /// while sources remain untried -- there is nothing yet to back off from.
  Duration? _delayBefore(int n) {
    if (n < widget.urls.length) return Duration.zero;
    final index = n - widget.urls.length;
    return index < _backoff.length ? _backoff[index] : null;
  }

  Timer? _scheduled;
  Timer? _watchdog;

  /// Kept so a retry can evict it. ImageCache is keyed by provider, so without
  /// the eviction a re-resolve joins the in-flight load -- which for a hung
  /// request means waiting on the very thing that failed to arrive.
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _armWatchdog();
  }

  /// Cancelled by the first frame; see frameBuilder.
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_stall, () {
      if (mounted) _scheduleRetry();
    });
  }

  @override
  void didUpdateWidget(_Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // By value: the parent rebuilds this list every time, so identity would see
    // a new cover on every build and restart the walk for ever.
    if (!listEquals(widget.urls, oldWidget.urls)) {
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

  /// Queues the next attempt. Guarded against double-queueing, since
  /// errorBuilder runs on every rebuild rather than only on the failure.
  void _scheduleRetry() {
    if (_scheduled != null) return;
    final delay = _delayBefore(_attempt + 1);
    if (delay == null) return;
    _scheduled = Timer(delay, () async {
      if (!mounted) return;
      // Even for a different host: cycling back later would otherwise be
      // answered out of the image cache with this failure.
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
    // LayoutBuilder rather than a size parameter, so this decodes correctly
    // wherever it is put. Undecoded, a 600px cover in a 48px tile holds a hundred
    // times the pixels it can show.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final decodeWidth = width.isFinite && width > 0
            ? (width * MediaQuery.devicePixelRatioOf(context)).round()
            : null;

        // Spelled out rather than Image.network, which keeps its provider to
        // itself -- and a retry has to be able to evict it.
        _provider = ResizeImage.resizeIfNeeded(
          decodeWidth,
          null,
          coverImageProvider(_url, store: CoverImageScope.maybeOf(context)),
        );

        return Image(
          image: _provider!,
          // A new key is what builds the fresh state that re-resolves.
          key: ValueKey(_attempt),
          fit: BoxFit.cover,
          // A 600px photo in a 48px tile aliases visibly at the default quality.
          filterQuality: FilterQuality.medium,
          // Title and artist are already beside it.
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              _watchdog?.cancel();
              _watchdog = null;
            }
            // Already cached: show at once rather than flickering through a fade.
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
          // Silent -- the placeholder stands -- but queues the next attempt:
          // nothing else would ever re-resolve this cover.
          errorBuilder: (context, error, stackTrace) {
            _scheduleRetry();
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}
