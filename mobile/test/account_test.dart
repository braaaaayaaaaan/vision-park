import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/app_theme.dart';
import 'package:visionpark_mobile/app/app_shell.dart';
import 'package:visionpark_mobile/data/models/driver_models.dart';
import 'package:visionpark_mobile/data/repositories/driver_repository.dart';
import 'package:visionpark_mobile/features/account/account_controller.dart';
import 'package:visionpark_mobile/features/account/account_screen.dart';

// Profile and vehicle examples are test fixtures only.
const profile = DriverProfile(
  id: 'test',
  fullName: 'Test Driver',
  email: 'driver@example.test',
  tenantName: 'Test Company',
  isActive: true,
);

class TestRepository implements DriverRepository {
  TestRepository({required this.readProfile, this.vehicles = const []});
  final Future<DriverProfile> Function() readProfile;
  final List<DriverVehicle> vehicles;
  @override
  Future<DriverProfile> getProfile() => readProfile();
  @override
  Future<List<DriverVehicle>> getVehicles() async => vehicles;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget screen(AccountController controller) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: AccountScreen(controller: controller, onVehiclesSelected: () {}),
  ),
);

void main() {
  testWidgets('profile is read-only and summary comes from vehicle records', (
    tester,
  ) async {
    final controller = AccountController(
      repository: TestRepository(
        readProfile: () async => profile,
        vehicles: [
          for (final status in ['approved', 'approved', 'pending', 'rejected'])
            DriverVehicle(
              id: status,
              plateNumber: 'TEST',
              registrationStatus: status,
            ),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    expect(find.text('Test Driver'), findsOneWidget);
    expect(find.text('driver@example.test'), findsOneWidget);
    expect(find.text('Test Company'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Approved Vehicles: 2'), findsOneWidget);
    expect(find.text('Pending Approval: 1'), findsOneWidget);
    await tester.ensureVisible(find.text('Personal Information'));
    await tester.tap(find.text('Personal Information'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Test Company'),
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('read-only here'), findsWidgets);
  });

  testWidgets(
    'disconnected data remains unavailable and empty reads show absence',
    (tester) async {
      final disconnected = AccountController();
      addTearDown(disconnected.dispose);
      await tester.pumpWidget(screen(disconnected));
      expect(find.textContaining('Not Connected.'), findsOneWidget);
      expect(find.text('Approved Vehicles: Unavailable'), findsOneWidget);
      expect(find.text('No Registered Vehicles'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      final empty = AccountController(
        repository: TestRepository(
          readProfile: () async => const DriverProfile(id: 'test'),
        ),
      );
      addTearDown(empty.dispose);
      await tester.pumpWidget(screen(empty));
      await tester.pumpAndSettle();
      expect(find.text('Not Provided'), findsNWidgets(3));
      expect(find.text('No Registered Vehicles'), findsOneWidget);
      expect(find.text('Approved Vehicles: 0'), findsOneWidget);
      expect(find.textContaining('Not Connected.'), findsNothing);
    },
  );

  testWidgets(
    'loading and failed read support retry without inventing profile',
    (tester) async {
      var request = Completer<DriverProfile>();
      final controller = AccountController(
        repository: TestRepository(readProfile: () => request.future),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      expect(find.text('Loading Account'), findsOneWidget);
      request.completeError(StateError('test failure'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to Load Account'), findsOneWidget);
      expect(find.text('Approved Vehicles: Unavailable'), findsOneWidget);
      request = Completer<DriverProfile>();
      await tester.tap(find.text('Try Again'));
      request.complete(profile);
      await tester.pumpAndSettle();
      expect(find.text('Test Driver'), findsOneWidget);
    },
  );

  testWidgets('My Vehicles navigates within the existing shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AppShell()),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Account'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, 'My Vehicles'));
    await tester.tap(find.widgetWithText(ListTile, 'My Vehicles'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Your Registered Vehicles'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  testWidgets(
    'security and sign out are explicitly unavailable and preserve state',
    (tester) async {
      final controller = AccountController(
        repository: TestRepository(readProfile: () async => profile),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      for (final (action, title) in [
        ('Security', 'Security Unavailable'),
        ('Sign Out', 'Sign Out Unavailable'),
      ]) {
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(controller.profile, same(profile));
        expect(controller.status, AccountStatus.ready);
      }
    },
  );

  for (final width in [320.0, 900.0]) {
    testWidgets('profile and help fit $width with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = AccountController(
        repository: TestRepository(readProfile: () async => profile),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Help & Support'));
      await tester.tap(find.text('Help & Support'));
      await tester.pumpAndSettle();
      for (final heading in [
        'Vehicle Approval',
        'ANPR Recognition',
        'Parking Allocation',
        'Navigation',
        'Parking Confirmation',
      ]) {
        expect(find.text(heading), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  }
}
