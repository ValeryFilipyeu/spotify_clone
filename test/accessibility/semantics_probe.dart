import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helpers for reading what a screen reader would actually be handed.
///
/// These walk the whole semantics tree rather than going through
/// `tester.getSemantics(finder)`, because a finder resolves to the nearest node
/// for a widget's render object -- and for composites like Slider, ListTile or
/// anything wrapped in Semantics, the annotation frequently lives on a different
/// node than the one you asked about.

/// The three checks Flutter ships for this: everything tappable has a name, and
/// is big enough to hit on either platform (48dp Android, 44pt iOS).
Future<void> expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
}

/// Every semantics node currently in the tree.
List<SemanticsData> allSemantics(WidgetTester tester) {
  final data = <SemanticsData>[];
  void walk(SemanticsNode node) {
    data.add(node.getSemanticsData());
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(semanticsRoot(tester));
  return data;
}

SemanticsNode semanticsRoot(WidgetTester tester) {
  var node = tester.getSemantics(find.byType(MaterialApp));
  while (node.parent != null) {
    node = node.parent!;
  }
  return node;
}

/// Every label and value in the tree, joined -- for asserting that some phrase
/// is spoken somewhere, without depending on how nodes happen to be merged.
String spokenText(WidgetTester tester) => allSemantics(tester)
    .expand((data) => [data.label, data.value, data.tooltip])
    .where((text) => text.isNotEmpty)
    .join(' | ');

/// Labels of every node flagged as a heading.
List<String> headings(WidgetTester tester) => [
  for (final data in allSemantics(tester))
    if (data.flagsCollection.isHeader && data.label.isNotEmpty) data.label,
];

/// Every custom action offered anywhere in the tree, by label.
Set<String> customActionLabels(WidgetTester tester) => {
  for (final data in allSemantics(tester))
    for (final id in data.customSemanticsActionIds ?? const <int>[])
      ?CustomSemanticsAction.getAction(id)?.label,
};

/// Whether the row containing [title] is marked selected. The flag sits on the
/// row's own node, above the node holding the title text.
bool rowIsSelected(WidgetTester tester, String title) {
  SemanticsNode? node = tester.getSemantics(find.text(title));
  while (node != null) {
    if (node.flagsCollection.isSelected == Tristate.isTrue) return true;
    node = node.parent;
  }
  return false;
}

/// What an icon-only control is actually named. Material's [Tooltip] publishes
/// its message as [SemanticsData.tooltip], NOT as the label -- and Flutter's own
/// labelled-tap-target guideline accepts either, so a tooltip is a real label,
/// just not in the field you would first reach for.
String spokenName(WidgetTester tester, Finder finder) {
  final data = tester.getSemantics(finder).getSemanticsData();
  return [data.label, data.tooltip].where((text) => text.isNotEmpty).join(' ');
}
