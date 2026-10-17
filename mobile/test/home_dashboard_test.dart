import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/app_theme.dart';
import 'package:visionpark_mobile/app/app_shell.dart';
import 'package:visionpark_mobile/data/models/dashboard_models.dart';
import 'package:visionpark_mobile/data/models/driver_models.dart';
import 'package:visionpark_mobile/data/repositories/dashboard_repository.dart';
import 'package:visionpark_mobile/features/home/home_controller.dart';
import 'package:visionpark_mobile/features/home/home_screen.dart';
import 'package:visionpark_mobile/features/home/widgets/active_session_card.dart';
import 'package:visionpark_mobile/features/home/widgets/occupancy_indicator.dart';
import 'package:visionpark_mobile/shared/formatting/malaysian_date_time.dart';

// Fixtures exist only in tests. No production repository supplies sample records.
const zone = ParkingZone(
  id: 'zone',
  name: 'Test Zone',
  levelId: 'level',
  levelName: 'Test Level',
  availableCapacity: 4,
);

ActiveParking parking({
  ParkingSessionStatus status = ParkingSessionStatus.allocated,
  String routeSessionId = 'session',
  double x = 1,
  bool withRoute = true,
}) {
  return ActiveParking(
    session: ParkingSession(
      id: 'session',
      vehicleId: 'vehicle',
      zoneId: 'zone',
      status: status,
      entryTime: DateTime.utc(2026),
    ),
    vehicle: const DriverVehicle(
      id: 'vehicle',
      plateNumber: 'TEST123',
      registrationStatus: 'approved',
    ),
    zone: zone,
    anprInformation: 'Plate Recognised',
    anprVerifiedAt: DateTime.utc(2026, 10, 16, 1, 30),
    route: withRoute
        ? ParkingRoute(
            sessionId: routeSessionId,
            distanceMetres: 42,
            nodes: [RouteNode(id: 'node', levelId: 'level', x: x, y: 2)],
          )
        : null,
  );
}

DashboardData dashboard({ActiveParking? active, bool empty = false}) {
  return DashboardData(
    profile: const DriverProfile(id: 'driver', tenantName: 'Test Company'),
    availability: ParkingAvailability(
      availableSpaces: empty ? 0 : 9,
      accessibleZoneCount: empty ? 0 : 3,
      levels: empty
          ? []
          : List.generate(
              3,
              (index) => LevelAvailability(
                id: 'level-$index',
                name: 'Test Level $index',
                availableSpaces: 4,
                totalSpaces: 16,
                occupancy: 0.75,
                zones: [
                  const ZoneAvailability(
                    zone: zone,
                    totalSpaces: 16,
                    occupancy: 0.75,
                  ),
                ],
              ),
            ),
    ),
    activeParking: active,
  );
}

class TestRepository implements DashboardRepository {
  TestRepository(this.read);
  final Future<DashboardData> Function() read;
  @override
  Future<DashboardData> getDashboard() => read();
}

Widget home(HomeController controller, {ValueChanged<int>? onTab}) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: HomeScreen(
        controller: controller,
        onTabSelected: onTab ?? (_) {},
        clock: () => DateTime.utc(2026, 10, 16, 1),
      ),
    ),
  );
}

void main() {
  test('greeting uses Malaysian time, not UTC', () {
    expect(
      MalaysianDateTime.greeting(DateTime.utc(2026, 1, 1, 4)),
      'Good Afternoon',
    );
    expect(
      MalaysianDateTime.greeting(DateTime.utc(2026, 1, 1, 10)),
      'Good Evening',
    );
    expect(
      MalaysianDateTime.greeting(DateTime.utc(2026, 1, 1, 23)),
      'Good Morning',
    );
  });

  testWidgets('disconnected is not an empty session and has no fake figures', (
    tester,
  ) async {
    final controller = HomeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(home(controller));
    expect(find.text('Not Connected'), findsNWidgets(2));
    expect(find.text('No Active Parking Session'), findsNothing);
    expect(find.text('Spaces Available'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'View Route'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('loading, failed read, retry and genuine empty state', (
    tester,
  ) async {
    var request = Completer<DashboardData>();
    final controller = HomeController(
      repository: TestRepository(() => request.future),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(home(controller));
    expect(find.text('Loading Parking Information'), findsNWidgets(2));
    request.completeError(StateError('test failure'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to Load Parking Information'), findsNWidgets(2));
    expect(find.text('No Active Parking Session'), findsNothing);
    request = Completer<DashboardData>();
    await tester.tap(find.text('Try Again').first);
    await tester.pump();
    request.complete(dashboard(empty: true));
    await tester.pumpAndSettle();
    expect(find.text('No Active Parking Session'), findsOneWidget);
    expect(find.textContaining('No Accessible Parking Levels'), findsOneWidget);
  });

  for (final entry in [
    (0.0, 'Available'),
    (0.749, 'Available'),
    (0.75, 'Nearly Full'),
    (0.999, 'Nearly Full'),
    (1.0, 'Full'),
  ]) {
    testWidgets('occupancy threshold ${entry.$1}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupancyIndicator(occupancy: entry.$1, totalSpaces: 100),
          ),
        ),
      );
      expect(find.text(entry.$2), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .color,
        entry.$2 == 'Available'
            ? OccupancyColours.available
            : entry.$2 == 'Full'
            ? OccupancyColours.full
            : OccupancyColours.nearlyFull,
      );
    });
  }

  testWidgets('zero capacity does not invent occupancy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OccupancyIndicator(occupancy: 0, totalSpaces: 0)),
    );
    expect(find.text('Occupancy Unavailable'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('View Route requires a matching valid allocated route', (
    tester,
  ) async {
    var navigations = 0;
    for (final item in [
      parking(withRoute: false),
      parking(routeSessionId: 'other'),
      parking(x: double.nan),
      parking(status: ParkingSessionStatus.occupied),
      parking(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActiveSessionCard(
                parking: item,
                onViewRoute: () => navigations++,
              ),
            ),
          ),
        ),
      );
      final button = find.widgetWithText(FilledButton, 'View Route');
      expect(
        tester.widget<FilledButton>(button).onPressed != null,
        item.hasValidRoute,
      );
      if (item.hasValidRoute) {
        await tester.ensureVisible(button);
        await tester.tap(button);
      }
      expect(find.text('16 Oct 2026, 09:30 MYT'), findsOneWidget);
    }
    expect(navigations, 1);
  });

  testWidgets('quick access and profile shortcut switch existing tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AppShell()),
    );
    await tester.tap(find.byTooltip('Open Account'));
    await tester.pumpAndSettle();
    expect(find.text('Your Profile Will Appear Here'), findsOneWidget);
    for (final entry in [
      ('My Vehicles', 'Your Vehicles Will Appear Here'),
      ('Parking History', 'Your Visits Will Appear Here'),
      ('Account', 'Your Profile Will Appear Here'),
    ]) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      final shortcut = find.widgetWithText(ListTile, entry.$1);
      await tester.ensureVisible(shortcut);
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
    }
  });

  for (final size in [const Size(320, 568), const Size(900, 600)]) {
    testWidgets(
      'populated dashboard at $size with large text and dynamic levels',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = HomeController(
          repository: TestRepository(() async => dashboard(active: parking())),
        );
        addTearDown(controller.dispose);
        int? selected;
        await tester.pumpWidget(
          home(controller, onTab: (index) => selected = index),
        );
        await tester.pumpAndSettle();
        expect(find.text('Test Company'), findsOneWidget);
        expect(
          find.text('9'),
          findsOneWidget,
        ); // Explicit total, not 3 levels * 4.
        expect(find.text('Test Level 2'), findsOneWidget);
        final route = find.widgetWithText(FilledButton, 'View Route');
        await tester.ensureVisible(route);
        await tester.tap(route);
        expect(selected, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
