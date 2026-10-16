import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/app_theme.dart';
import 'package:visionpark_mobile/data/models/driver_models.dart';
import 'package:visionpark_mobile/data/repositories/driver_repository.dart';
import 'package:visionpark_mobile/features/vehicles/vehicles_controller.dart';
import 'package:visionpark_mobile/features/vehicles/vehicles_screen.dart';
import 'package:visionpark_mobile/features/vehicles/widgets/registration_dialog.dart';
import 'package:visionpark_mobile/features/vehicles/widgets/vehicle_card.dart';

// Sample records are restricted to tests.
DriverVehicle vehicle(
  String status, {
  ParkingSessionStatus? session,
  bool known = true,
}) => DriverVehicle(
  id: status,
  plateNumber: 'TEST $status',
  registrationStatus: status,
  lastRecognitionAt: DateTime.utc(2026, 10, 16, 1, 30),
  sessionInformationAvailable: known,
  removalPermitted: true,
  activeSession: session == null
      ? null
      : ParkingSession(
          id: 'session',
          vehicleId: status,
          zoneId: 'zone',
          status: session,
          entryTime: DateTime.utc(2026, 10, 16),
        ),
);

class TestRepository implements DriverRepository {
  TestRepository(this.read);
  final Future<List<DriverVehicle>> Function() read;
  @override
  Future<List<DriverVehicle>> getVehicles() => read();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget screen(VehiclesController controller) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: VehiclesScreen(controller: controller)),
);

void main() {
  testWidgets('disconnected counts are unknown rather than zero', (
    tester,
  ) async {
    final controller = VehiclesController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    expect(find.text('Approved Vehicles: Unavailable'), findsOneWidget);
    expect(find.textContaining('Not Connected'), findsOneWidget);
    expect(find.text('No Registered Vehicles'), findsNothing);
  });

  testWidgets('loading, error, retry and confirmed empty are distinct', (
    tester,
  ) async {
    var request = Completer<List<DriverVehicle>>();
    final controller = VehiclesController(
      repository: TestRepository(() => request.future),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    expect(find.text('Loading Vehicles'), findsOneWidget);
    request.completeError(StateError('test'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to Load Vehicles'), findsOneWidget);
    request = Completer<List<DriverVehicle>>();
    await tester.ensureVisible(find.text('Try Again'));
    await tester.tap(find.text('Try Again'));
    request.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No Registered Vehicles'), findsOneWidget);
    expect(find.text('Approved Vehicles: 0'), findsOneWidget);
  });

  testWidgets('filters keep rejected vehicles accessible through All', (
    tester,
  ) async {
    final controller = VehiclesController(
      repository: TestRepository(
        () async => [
          vehicle('approved'),
          vehicle('pending'),
          vehicle('rejected'),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    expect(find.byType(VehicleCard), findsNWidgets(3));
    for (final (label, status) in [
      ('Approved', 'approved'),
      ('Pending', 'pending'),
    ]) {
      final chip = find.widgetWithText(ChoiceChip, label);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(find.byType(VehicleCard), findsOneWidget);
      expect(find.text('TEST $status'), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsOneWidget);
    expect(controller.vehicles.length, 3);
  });

  testWidgets(
    'registration validates, normalises gently, and never adds records',
    (tester) async {
      final controller = VehiclesController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.tap(find.text('Register New Vehicle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number plate.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        '  special-plate 12  ',
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      expect(find.text('SPECIAL-PLATE 12'), findsOneWidget);
      expect(find.textContaining('Registration Unavailable.'), findsOneWidget);
      expect(controller.vehicles, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(RegistrationDialog), findsNothing);
    },
  );

  testWidgets('removal cancellation and confirmation never mutate records', (
    tester,
  ) async {
    final record = vehicle('approved');
    final controller = VehiclesController(
      repository: TestRepository(() async => [record]),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    final remove = find.widgetWithText(OutlinedButton, 'Remove Vehicle');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.textContaining('Remove TEST approved'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Removal Unavailable'), findsNothing);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove Vehicle'));
    await tester.pumpAndSettle();
    expect(find.text('Removal Unavailable'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(controller.vehicles.single, same(record));
    expect(find.text('TEST approved'), findsOneWidget);
  });

  for (final status in [
    ParkingSessionStatus.allocated,
    ParkingSessionStatus.occupied,
    null,
  ]) {
    testWidgets('removal blocked for active or unknown session $status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VehicleCard(
                vehicle: vehicle(
                  'approved',
                  session: status,
                  known: status != null,
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Remove Vehicle'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();
      expect(
        find.text('Last Recognition: 16 Oct 2026, 09:30 MYT'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Administrator approval and ANPR recognition are separate checks.',
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'small screen and enlarged text support cards and form with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = VehiclesController(
        repository: TestRepository(() async => [vehicle('approved')]),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      final details = find.text('View Details');
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Register New Vehicle'));
      await tester.tap(find.text('Register New Vehicle'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
