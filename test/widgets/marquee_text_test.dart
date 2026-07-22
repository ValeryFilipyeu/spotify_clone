import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/widgets/marquee_text.dart';

Widget _host(String text, double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: MarqueeText(text)),
        ),
      ),
    );

void main() {
  testWidgets('text that fits is shown statically (does not move)', (tester) async {
    await tester.pumpWidget(_host('OK', 300));
    await tester.pump(); // layout
    await tester.pump(); // post-frame sync (no-op: it fits)

    expect(find.text('OK'), findsOneWidget);
    final dxStart = tester.getTopLeft(find.text('OK')).dx;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getTopLeft(find.text('OK')).dx, dxStart); // never scrolled
  });

  testWidgets('text that overflows scrolls left over time', (tester) async {
    const long = 'A very very very long track title that cannot possibly fit here';
    await tester.pumpWidget(_host(long, 120));
    await tester.pump(); // layout -> measures overflow, schedules sync
    await tester.pump(); // post-frame sync -> controller starts repeating

    final dxStart = tester.getTopLeft(find.text(long)).dx;
    // Advance past the start pause (1200ms) and into the scroll-out phase.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.getTopLeft(find.text(long)).dx, lessThan(dxStart));
  });
}
