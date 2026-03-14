import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:syncache_example/main.dart';

void main() {
  testWidgets('Home page displays demo cards', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SyncacheExampleApp());

    // Verify the app title is displayed.
    expect(find.text('Syncache Example'), findsOneWidget);

    // Verify demo cards are displayed.
    expect(find.text('Offline-First Caching'), findsOneWidget);
    expect(find.text('Reactive Streams (watch)'), findsOneWidget);
    expect(find.text('Optimistic Mutations'), findsOneWidget);

    // Verify network status toggle is displayed.
    expect(find.text('Network Status'), findsOneWidget);
  });

  testWidgets('Network toggle works', (WidgetTester tester) async {
    await tester.pumpWidget(const SyncacheExampleApp());

    // Initially online
    expect(find.text('Online'), findsOneWidget);

    // Toggle the switch
    await tester.tap(find.byType(Switch));
    await tester.pump();

    // Should now be offline
    expect(find.text('Offline'), findsOneWidget);
  });
}
