// Smoke test for the example app.
//
// The example app is a Syncache demo (not the `flutter create` counter
// template this file once held), so the test verifies that the app builds
// and renders its demo home page.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:syncache_flutter_example/main.dart';

void main() {
  testWidgets('example app builds and shows the demo home page',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
