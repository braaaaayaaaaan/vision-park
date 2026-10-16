import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/app_theme.dart';
import 'package:visionpark_mobile/data/models/driver_models.dart';
import 'package:visionpark_mobile/data/repositories/driver_repository.dart';
import 'package:visionpark_mobile/features/history/history_controller.dart';
import 'package:visionpark_mobile/features/history/history_screen.dart';
import 'package:visionpark_mobile/features/history/widgets/history_session_card.dart';

final now = DateTime.parse('2026-10-16T10:00:00+08:00');
ParkingSession session(
  String id,
  String entry, {
  String vehicle = 'a',
  String? exit,
  ParkingSessionStatus status = ParkingSessionStatus.completed,
}) => ParkingSession(
  id: id,
  vehicleId: vehicle,
  zoneId: 'zone',
  status: status,
  entryTime: DateTime.parse(entry),
  exitTime: exit == null ? null : DateTime.parse(exit),
  plateNumber: 'TEST $vehicle',
  zoneName: 'Test Zone',
  levelName: 'Test Level',
);
const vehicles = [
  DriverVehicle(id: 'a', plateNumber: 'TEST a', registrationStatus: 'approved'),
  DriverVehicle(id: 'b', plateNumber: 'TEST b', registrationStatus: 'approved'),
];

class TestRepository implements DriverRepository {
  TestRepository(this.read);
  final Future<List<ParkingSession>> Function(int offset) read;
  @override
  Future<List<DriverVehicle>> getVehicles() async => vehicles;
  @override
  Future<List<ParkingSession>> getParkingHistory({
    required int offset,
    required int limit,
  }) => read(offset);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HistoryController controllerFor(List<ParkingSession> records) =>
    HistoryController(
      clock: () => now,
      repository: TestRepository((offset) async => offset == 0 ? records : []),
    );
Widget screen(HistoryController controller) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: HistoryScreen(controller: controller)),
);

void main() {
  test('calendar ranges use Malaysian midnight across UTC dates', () async {
    final controller = controllerFor([
      session('today', '2026-10-15T16:00:00Z'),
      session('before-today', '2026-10-15T15:59:59Z'),
      session('three', '2026-10-13T16:00:00Z'),
      session('before-three', '2026-10-13T15:59:59Z'),
      session('seven', '2026-10-09T16:00:00Z'),
      session('before-seven', '2026-10-09T15:59:59Z'),
      session('tomorrow', '2026-10-16T16:00:00Z'),
    ]);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.days, 7);
    expect(controller.filteredSessions.map((s) => s.id), [
      'today',
      'before-today',
      'three',
      'before-three',
      'seven',
    ]);
    controller.selectDays(3);
    expect(controller.filteredSessions.map((s) => s.id), [
      'today',
      'before-today',
      'three',
    ]);
    controller.selectDays(1);
    expect(controller.filteredSessions.map((s) => s.id), ['today']);
  });

  test(
    'filters, newest-first order and completed-only averages agree',
    () async {
      final controller = controllerFor([
        session('older', '2026-10-14T00:00:00Z', exit: '2026-10-14T02:00:00Z'),
        session(
          'newer',
          '2026-10-16T00:00:00Z',
          exit: '2026-10-16T01:00:00Z',
          vehicle: 'b',
        ),
        session('missing', '2026-10-15T00:00:00Z'),
        session(
          'invalid',
          '2026-10-15T01:00:00Z',
          exit: '2026-10-15T00:00:00Z',
        ),
        session(
          'active',
          '2026-10-15T02:00:00Z',
          exit: '2026-10-15T04:00:00Z',
          status: ParkingSessionStatus.occupied,
        ),
      ]);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.filteredSessions.first.id, 'newer');
      expect(controller.filteredSessions.last.id, 'older');
      expect(controller.averageDuration, const Duration(minutes: 90));
      controller.selectVehicle('a');
      expect(controller.filteredSessions.length, 4);
      expect(controller.averageDuration, const Duration(hours: 2));
      controller.selectDays(1);
      expect(controller.filteredSessions, isEmpty);
      expect(controller.averageDuration, isNull);
    },
  );

  test('all pages are read before analytics become ready', () async {
    final offsets = <int>[];
    final controller = HistoryController(
      clock: () => now,
      repository: TestRepository((offset) async {
        offsets.add(offset);
        return offset < 2 ? [session('$offset', '2026-10-16T00:00:00Z')] : [];
      }),
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(offsets, [0, 1, 2]);
    expect(controller.filteredSessions.length, 2);
  });

  testWidgets('disconnected does not invent analytics', (tester) async {
    final controller = HistoryController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.textContaining('Not Connected'), findsOneWidget);
    expect(find.text('No Parking Sessions'), findsNothing);
  });

  testWidgets('loading, error, retry and empty states remain distinct', (
    tester,
  ) async {
    var request = Completer<List<ParkingSession>>();
    final controller = HistoryController(
      clock: () => now,
      repository: TestRepository((_) => request.future),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pump();
    expect(find.text('Loading Parking History'), findsOneWidget);
    request.completeError(StateError('test'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to Load Parking History'), findsOneWidget);
    request = Completer<List<ParkingSession>>();
    await tester.ensureVisible(find.text('Try Again'));
    await tester.tap(find.text('Try Again'));
    request.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No Parking Sessions'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('date and vehicle controls update cards and summary', (
    tester,
  ) async {
    final controller = controllerFor([
      session('one', '2026-10-16T00:00:00Z', exit: '2026-10-16T01:00:00Z'),
      session('two', '2026-10-14T00:00:00Z', vehicle: 'b'),
    ]);
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    expect(find.byType(HistorySessionCard), findsNWidgets(2));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 1 Day'));
    await tester.pumpAndSettle();
    expect(find.byType(HistorySessionCard), findsOneWidget);
    await tester.ensureVisible(find.byType(DropdownButton<String>));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TEST b').last);
    await tester.pumpAndSettle();
    expect(find.text('No Parking Sessions'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  for (final width in [320.0, 900.0]) {
    testWidgets(
      'incomplete card and details fit width $width with large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final controller = controllerFor([
          session(
            'incomplete',
            '2026-10-16T00:00:00Z',
            status: ParkingSessionStatus.occupied,
          ),
        ]);
        addTearDown(controller.dispose);
        await tester.pumpWidget(screen(controller));
        await tester.pumpAndSettle();
        expect(find.text('Exit: Not Recorded'), findsOneWidget);
        expect(find.text('Duration: Unavailable'), findsOneWidget);
        await tester.ensureVisible(find.text('View Details'));
        await tester.tap(find.text('View Details'));
        await tester.pumpAndSettle();
        expect(find.text('Parking Confirmed: Not Recorded'), findsOneWidget);
        expect(find.text('Entry: 16 Oct 2026, 08:00 MYT'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
