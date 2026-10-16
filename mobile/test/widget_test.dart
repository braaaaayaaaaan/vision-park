import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/vision_park_app.dart';

void main() {
  testWidgets('opens Home and switches between all five driver tabs', (
    tester,
  ) async {
    await tester.pumpWidget(const VisionParkApp());

    expect(find.text('Welcome to VisionPark'), findsOneWidget);
    expect(find.text('Your Parking Overview'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.byType(FloatingActionButton), findsNothing);

    const destinations = {
      'Navigate': 'Your Route Will Appear Here',
      'Vehicles': 'Your Vehicles Will Appear Here',
      'History': 'Your Visits Will Appear Here',
      'Account': 'Your Profile Will Appear Here',
      'Home': 'Your Parking Overview',
    };

    for (final destination in destinations.entries) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(destination.key),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(destination.value), findsOneWidget);
      expect(find.textContaining('Not Connected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(900, 600),
  ]) {
    testWidgets('tabs remain usable at $size with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(const VisionParkApp());
      for (final label in [
        'Home',
        'Navigate',
        'Vehicles',
        'History',
        'Account',
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SingleChildScrollView), findsOneWidget);
      }
    });
  }
}
