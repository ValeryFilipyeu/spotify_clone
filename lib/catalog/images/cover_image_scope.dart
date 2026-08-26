import 'package:flutter/widgets.dart';

import '../../storage/image_byte_store.dart';

/// Hands the cover cache to every [CoverArt] beneath it, rather than threading a
/// storage detail through a dozen widget signatures.
///
/// Not a `RepositoryProvider`, the house style, for one reason: its lookup throws
/// when nothing is registered. Here absence is a supported state -- the web has
/// no store -- so [maybeOf] returning null keeps "no cache" a first-class case.
class CoverImageScope extends InheritedWidget {
  const CoverImageScope({super.key, required this.store, required super.child});

  /// Null where there is nowhere to cache to. See [openImageByteStore].
  final ImageByteStore? store;

  static ImageByteStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoverImageScope>()?.store;

  @override
  bool updateShouldNotify(CoverImageScope oldWidget) => store != oldWidget.store;
}
