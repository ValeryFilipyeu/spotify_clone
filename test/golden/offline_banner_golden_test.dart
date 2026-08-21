@TestOn('vm')
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_status.dart';
import 'package:spotify_clone/shell/widgets/offline_banner.dart';

import '../helpers/fake_offline_status.dart';
import 'golden_harness.dart';

Widget _banner(double width) => RepositoryProvider<OfflineStatus>.value(
  value: FakeOfflineStatus(offline: true),
  child: SizedBox(width: width, child: const OfflineBanner()),
);

/// The offline strip is a piece of *reassurance*, and that is a visual property
/// rather than a functional one.
///
/// Everything about it that a finder can check is already checked in
/// `test/shell/widgets/offline_banner_test.dart`: the text is there, the icon is
/// beside it, the whole thing collapses when the catalog is reachable. None of
/// that distinguishes a discreet grey notice from a full-width alarm, and getting
/// that wrong is the entire way this widget can fail -- a strip that shouts makes
/// a working app look broken, which is the opposite of its job.
void main() {
  setUpAll(setUpGoldens);

  group('OfflineBanner', () {
    testWidgets('on a phone', (tester) async {
      await expectGolden(
        tester,
        'offline_banner',
        size: const GoldenSize(390, 60),
        child: _banner(390),
      );
    });

    testWidgets('on a screen too narrow for the whole sentence', (tester) async {
      // 240 is narrower than any phone, and deliberately so: what is under test is
      // the moment the text runs out of room, and forcing it here is cheaper than
      // hoping a real width happens to sit near the boundary. The row should
      // ellipsize and stay centred rather than push the icon out.
      await expectGolden(
        tester,
        'offline_banner_narrow',
        size: const GoldenSize(240, 60),
        child: _banner(240),
      );
    });
  });
}
