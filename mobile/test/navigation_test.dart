import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/app/app_theme.dart';
import 'package:visionpark_mobile/data/models/dashboard_models.dart';
import 'package:visionpark_mobile/data/models/driver_models.dart';
import 'package:visionpark_mobile/data/models/navigation_models.dart';
import 'package:visionpark_mobile/data/repositories/driver_repository.dart';
import 'package:visionpark_mobile/features/navigation/navigation_controller.dart';
import 'package:visionpark_mobile/features/navigation/navigation_screen.dart';
import 'package:visionpark_mobile/features/navigation/route_geometry.dart';
import 'package:visionpark_mobile/features/navigation/widgets/parking_map.dart';

// Synthetic graph fixtures are only used by tests.
const a = RouteNode(
  id: 'a',
  levelId: 'lower',
  x: -10,
  y: 0,
  nodeType: 'building_entrance',
);
const b = RouteNode(id: 'b', levelId: 'lower', x: 90, y: 50);
const c = RouteNode(id: 'c', levelId: 'upper', x: 0, y: 0);
const d = RouteNode(id: 'd', levelId: 'upper', x: 20, y: 80);
ParkingGraph graph({List<GraphEdge>? edges, List<RouteNode>? nodes}) =>
    ParkingGraph(
      levels: const [
        MapLevel(id: 'lower', name: 'Test Lower'),
        MapLevel(id: 'upper', name: 'Test Upper'),
      ],
      nodes: nodes ?? [d, b, a, c],
      edges:
          edges ??
          const [
            GraphEdge(fromId: 'a', toId: 'b'),
            GraphEdge(
              fromId: 'b',
              toId: 'c',
              transitionLabel: 'Test Transition',
            ),
            GraphEdge(fromId: 'c', toId: 'd'),
          ],
    );
NavigationData data({
  ParkingSessionStatus status = ParkingSessionStatus.allocated,
  bool allowed = true,
  bool empty = false,
  ParkingGraph? map,
  String routeSession = 'session',
}) => NavigationData(
  parking: empty
      ? null
      : ActiveParking(
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
          zone: const ParkingZone(
            id: 'zone',
            name: 'Test Destination',
            levelId: 'upper',
            levelName: 'Test Upper',
            availableCapacity: 1,
          ),
          route: ParkingRoute(
            sessionId: routeSession,
            distanceMetres: 52,
            nodes: [a, b, c, d],
          ),
        ),
  graph: map ?? graph(),
  confirmationAllowed: allowed,
);

class TestRepository implements DriverRepository {
  TestRepository(this.read);
  final Future<NavigationData> Function() read;
  @override
  Future<NavigationData> getNavigation() => read();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget screen(NavigationController controller) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(body: NavigationScreen(controller: controller)),
);

void main() {
  test('very small coordinate spans remain finite', () {
    const first = RouteNode(id: 'tiny-a', levelId: 'level', x: 0, y: 0);
    const last = RouteNode(id: 'tiny-b', levelId: 'level', x: 1e-310, y: 0);
    final projection = CoordinateProjection([
      first,
      last,
    ], const Size(300, 300));
    expect(projection.project(first).dx, closeTo(32, 0.001));
    expect(projection.project(last).dx, closeTo(268, 0.001));
    expect(projection.project(last).dy.isFinite, isTrue);
  });
  test(
    'route order is preserved; cross-floor pairs never become 2D segments',
    () {
      final geometry = RouteGeometry(graph(), ['a', 'b', 'c', 'd']);
      expect(geometry.error, isNull);
      expect(geometry.orderedNodes.map((node) => node.id), [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(geometry.segments('lower'), [(a, b)]);
      expect(geometry.segments('upper'), [(c, d)]);
      expect(geometry.transitions, [(b, c, 'Test Transition')]);
    },
  );
  test(
    'missing, reverse, inactive links and invalid coordinates are rejected',
    () {
      expect(RouteGeometry(graph(), ['b', 'a']).error, isNotNull);
      expect(RouteGeometry(graph(), ['missing']).error, isNotNull);
      expect(RouteGeometry(graph(), []).error, isNotNull);
      expect(RouteGeometry(graph(nodes: [a, a]), ['a']).error, isNotNull);
      expect(
        RouteGeometry(
          graph(
            nodes: [
              const RouteNode(id: 'a', levelId: 'lower', x: double.nan, y: 0),
            ],
          ),
          ['a'],
        ).error,
        isNotNull,
      );
      expect(
        RouteGeometry(
          graph(
            edges: [const GraphEdge(fromId: 'a', toId: 'b', isActive: false)],
          ),
          ['a', 'b'],
        ).error,
        isNotNull,
      );
    },
  );
  test(
    'coordinate projection fits supplied bounds and preserves aspect ratio',
    () {
      final projection = CoordinateProjection([a, b], const Size(300, 300));
      final start = projection.project(a);
      final end = projection.project(b);
      expect(start.dx, closeTo(32, 0.001));
      expect(end.dx, closeTo(268, 0.001));
      expect((end.dx - start.dx) / (end.dy - start.dy), closeTo(2, 0.001));
      expect(
        CoordinateProjection([a], const Size(300, 300)).project(a),
        const Offset(150, 150),
      );
    },
  );
  testWidgets(
    'dynamic floors select the correct painter and transition labels',
    (tester) async {
      final controller = NavigationController(
        repository: TestRepository(() async => data()),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      expect(
        find.text('Test Transition: Test Lower to Test Upper'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Detailed turn instructions are unavailable. Follow the highlighted fixed route and posted signs.',
        ),
        findsOneWidget,
      );
      final upper = find.widgetWithText(ChoiceChip, 'Test Upper (Destination)');
      await tester.ensureVisible(upper);
      await tester.tap(upper);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ParkingMap>(find.byType(ParkingMap)).levelId,
        'upper',
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(ParkingMap),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter!
              as ParkingMapPainter;
      expect(painter.geometry.segments(painter.levelId), [(c, d)]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('disconnected and loading states have no map or confirmation', (
    tester,
  ) async {
    final controller = NavigationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    expect(find.textContaining('Not Connected'), findsOneWidget);
    expect(find.byType(ParkingMap), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, "I've Parked"),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    final request = Completer<NavigationData>();
    final loading = NavigationController(
      repository: TestRepository(() => request.future),
    );
    addTearDown(loading.dispose);
    await tester.pumpWidget(screen(loading));
    expect(find.text('Loading Navigation'), findsOneWidget);
    request.completeError(StateError('test'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to Load Navigation'), findsOneWidget);
  });
  for (final value in [
    data(empty: true),
    data(status: ParkingSessionStatus.completed),
    data(status: ParkingSessionStatus.occupied),
    data(allowed: false),
  ]) {
    testWidgets(
      'confirmation restrictions ${value.parking?.session.status} ${value.confirmationAllowed}',
      (tester) async {
        final controller = NavigationController(
          repository: TestRepository(() async => value),
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(screen(controller));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, "I've Parked"),
              )
              .onPressed,
          isNull,
        );
        if (!controller.hasActiveSession) {
          expect(find.text('No Active Parking Session'), findsOneWidget);
          expect(find.byType(ParkingMap), findsNothing);
        }
      },
    );
  }
  testWidgets('invalid route is explained without drawing a fabricated map', (
    tester,
  ) async {
    final controller = NavigationController(
      repository: TestRepository(() async => data(routeSession: 'other')),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    expect(find.textContaining('Route Unavailable'), findsOneWidget);
    expect(find.byType(ParkingMap), findsNothing);
  });
  testWidgets(
    'confirmation cancel and confirm preserve the allocated session',
    (tester) async {
      final controller = NavigationController(
        repository: TestRepository(() async => data()),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(screen(controller));
      await tester.pumpAndSettle();
      final parked = find.text("I've Parked");
      await tester.ensureVisible(parked);
      await tester.tap(parked);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmation Unavailable'), findsNothing);
      await tester.tap(parked);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmation Unavailable'), findsOneWidget);
      expect(
        controller.data!.parking!.session.status,
        ParkingSessionStatus.allocated,
      );
    },
  );
  testWidgets('small screen supports map and large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = NavigationController(
      repository: TestRepository(() async => data()),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(screen(controller));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Route Directions'));
    expect(find.byType(ParkingMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
