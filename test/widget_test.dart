// Basic widget tests for the PlateRunner application.
//
// The original counter-oriented tests were removed after migrating to the
// LiveScan prototype. These placeholder tests ensure the application
// builds and the primary screen renders expected scaffold elements.
//
// Future additions:
//  - Golden tests for overlay rendering
//  - Pumping synthetic pipeline events to validate recent plates list
//  - Permission flow UI states
//
// References:
//  - lib/main.dart
//  - lib/app/pipeline/recognition_pipeline.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plate_runner/main.dart';
import 'package:plate_runner/shared/config/runtime_config.dart';

void main() {
  group('PlateRunnerApp smoke tests', () {
    testWidgets('app builds and shows Live Scan title', (tester) async {
      final config = InMemoryRuntimeConfigService.withDefaults();

      await tester.pumpWidget(PlateRunnerApp(configService: config));
      await tester.pumpAndSettle();

      // Verify the AppBar title of the LiveScanPage.
      expect(find.text('Live Scan (Prototype)'), findsOneWidget);

      // Basic sanity: recent plates section header present.
      expect(find.text('Recent Plates'), findsOneWidget);
    });

    testWidgets('tapping Start toggles to Stop (pipeline start)', (tester) async {
      final config = InMemoryRuntimeConfigService.withDefaults();
      await tester.pumpWidget(PlateRunnerApp(configService: config));
      await tester.pumpAndSettle();

      // Ensure initial button label.
      final startBtn = find.widgetWithText(FloatingActionButton, 'Start');
      expect(startBtn, findsOneWidget);

      await tester.tap(startBtn);
      await tester.pump(); // allow setState
      // After starting, label should flip to Stop.
      expect(find.widgetWithText(FloatingActionButton, 'Stop'), findsOneWidget);
    });
  });
}