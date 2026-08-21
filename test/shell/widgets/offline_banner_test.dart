import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_status.dart';
import 'package:spotify_clone/shell/widgets/offline_banner.dart';

import '../../accessibility/semantics_probe.dart';
import '../../helpers/fake_offline_status.dart';

final _notice = find.textContaining('offline');

/// A stream event takes two frames to become a picture: the first pump delivers it
/// to the [StreamBuilder], whose `setState` lands *after* that frame has already
/// been drawn, and the second renders the result. One pump looks like a widget
/// that ignores its stream.
Future<void> pumpStatusChange(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  Future<void> pumpBanner(WidgetTester tester, FakeOfflineStatus status) async {
    addTearDown(status.close);
    await tester.pumpWidget(
      MaterialApp(
        home: RepositoryProvider<OfflineStatus>.value(
          value: status,
          child: const Scaffold(bottomNavigationBar: OfflineBanner()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says nothing at all while the catalog is reachable', (tester) async {
    await pumpBanner(tester, FakeOfflineStatus());

    expect(_notice, findsNothing);
    // Not merely invisible: no height, so the shell's chrome is exactly as tall as
    // it was before this widget existed. (The width is the Scaffold's -- a bottom
    // bar is given a tight one whatever it puts in it.)
    expect(tester.getSize(find.byType(OfflineBanner)).height, 0);
  });

  testWidgets('is already showing when it is built after the network dropped', (tester) async {
    // The case that justifies OfflineStatus having a current value at all. This
    // widget is rebuilt on every tab switch and route push, so a stream of changes
    // alone would leave it blank for the rest of the outage.
    await pumpBanner(tester, FakeOfflineStatus(offline: true));

    expect(_notice, findsOneWidget);
  });

  testWidgets('appears when the catalog stops answering, and leaves again', (tester) async {
    final status = FakeOfflineStatus();
    await pumpBanner(tester, status);

    status.flip(offline: true);
    await pumpStatusChange(tester);
    expect(_notice, findsOneWidget);

    status.flip(offline: false);
    await pumpStatusChange(tester);
    expect(_notice, findsNothing);
  });

  testWidgets('announces itself rather than waiting to be found', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBanner(tester, FakeOfflineStatus(offline: true));

    // A screen reader user has even less to go on here than a sighted one: there
    // is no error, no spinner, and nothing focusable to stumble across -- the only
    // sign is a line of text that appeared on its own.
    final live = allSemantics(
      tester,
    ).where((data) => data.flagsCollection.isLiveRegion && data.label.contains('offline'));
    expect(live, isNotEmpty);

    handle.dispose();
  });

  testWidgets('keeps the icon and the text together in the middle', (tester) async {
    // Tested on a wide surface, and it has to be. `flutter test` draws every glyph
    // as a filled box, which is wider than the real letterform, so at phone width
    // this sentence already fills the row and there is no free space for the
    // centring to be wrong about. Give it 800 and the difference between a text
    // that takes what it needs (Flexible) and one that claims the row (Expanded)
    // becomes visible: only the first leaves the pair in the middle.
    await pumpBanner(tester, FakeOfflineStatus(offline: true));

    final row = tester.getRect(find.byType(OfflineBanner));
    final icon = tester.getRect(find.byIcon(Icons.cloud_off));
    final text = tester.getRect(_notice);

    expect(icon.left, greaterThan(row.left + 32), reason: 'not flush against the padding');
    expect(row.right - text.right, closeTo(icon.left - row.left, 2), reason: 'even margins');
  });

  testWidgets('gives the text less room rather than pushing the icon out', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpBanner(tester, FakeOfflineStatus(offline: true));

    // Flexible rather than Expanded: on a narrow screen the text ellipsizes and
    // the pair stays centred, instead of the text claiming the row and shoving the
    // icon to the edge.
    expect(tester.takeException(), isNull);
    final icon = tester.getRect(find.byIcon(Icons.cloud_off));
    final text = tester.getRect(_notice);
    expect(icon.right, lessThanOrEqualTo(text.left));
    expect(icon.center.dy, closeTo(text.center.dy, 1));
  });
}
