import 'package:flutter/widgets.dart';

import '../../storage/image_byte_store.dart';

/// Hands the cover cache to every [CoverArt] beneath it.
///
/// An [InheritedWidget] rather than a constructor argument because [CoverArt] is
/// built in a dozen places, several of them inside list builders, and threading a
/// store through all of them would put a storage detail in the signature of every
/// widget on the way down.
///
/// A plain `RepositoryProvider` would have been the house style, and does not fit
/// for one reason: its lookup throws when nothing is registered. That is the right
/// behaviour for a repository the app cannot work without, and the wrong one here,
/// where absence is a supported state -- the web has no store, and neither does
/// any of the widget tests written before this existed. [maybeOf] returning null
/// is what keeps "no cache" a first-class case rather than a missing dependency.
class CoverImageScope extends InheritedWidget {
  const CoverImageScope({super.key, required this.store, required super.child});

  /// Null where there is nowhere to cache to. See [openImageByteStore].
  final ImageByteStore? store;

  static ImageByteStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CoverImageScope>()?.store;

  @override
  bool updateShouldNotify(CoverImageScope oldWidget) => store != oldWidget.store;
}
