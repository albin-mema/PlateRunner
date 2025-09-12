// Widget tests for PlateRunner counter app.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:plate_runner/main.dart';

void main() {
  group('CounterPage', () {
    testWidgets('starts at zero', (tester) async {
      await tester.pumpWidget(const PlateRunnerApp());
      final counterText = find.byKey(const Key('counter_value'));
      expect(counterText, findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('increments when increment button pressed', (tester) async {
      await tester.pumpWidget(const PlateRunnerApp());
      final incButton = find.byKey(const Key('increment_button'));
      expect(incButton, findsOneWidget);
      await tester.tap(incButton);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('decrements when decrement button pressed (not below zero)', (tester) async {
      await tester.pumpWidget(const PlateRunnerApp());

      final decButton = find.byKey(const Key('decrement_button'));
      final incButton = find.byKey(const Key('increment_button'));

      // Initial should be zero; tapping decrement should keep at zero.
      expect(find.text('0'), findsOneWidget);
      await tester.tap(decButton);
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget, reason: 'Should not go negative');

      // Increment twice -> 2
      await tester.tap(incButton);
      await tester.tap(incButton);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);

      // Decrement once -> 1
      await tester.tap(decButton);
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      // Decrement again -> 0
      await tester.tap(decButton);
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);

      // Further decrement stays at 0
      await tester.tap(decButton);
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
    });


  });
}