import '../data/repositories/history_repository.dart';
import '../data/repositories/vehicle_repository.dart';
import '../data/repositories/assigned_route_repository.dart';
import '../data/repositories/availability_repository.dart';

import 'package:flutter/material.dart';

import '../data/repositories/active_session_repository.dart';
import '../data/repositories/auth_repository.dart';

import '../features/account/account_screen.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/navigation/navigation_screen.dart';
import '../features/vehicles/vehicles_screen.dart';
import 'app_config.dart';
import 'app_theme.dart';
import 'driver_bottom_navigation.dart';
import '../data/services/password_change.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    this.onSignOut,
    this.passwordChange,
    this.profile,
    this.activeSessionRepository,
    this.availabilityRepository,
    this.routeRepository,
    this.vehicleRepository,
    this.historyRepository,
    super.key,
  });

  final Future<void> Function()? onSignOut;
  final PasswordChangeService? passwordChange;
  final AuthProfile? profile;
  final ActiveSessionRepository? activeSessionRepository;
  final AvailabilityRepository? availabilityRepository;
  final AssignedRouteRepository? routeRepository;
  final VehicleRepository? vehicleRepository;
  final HistoryRepository? historyRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  int _parkingRevision = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_parking_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.small),
            const Text(AppConfig.name),
          ],
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            HomeScreen(
              fullName: widget.profile?.fullName,
              companyName: widget.profile?.companyName,
              refreshRevision: _parkingRevision,
              activeSessionRepository: widget.activeSessionRepository,
              availabilityRepository: widget.availabilityRepository,
              isVisible: _selectedIndex == 0,
              onSignOut: widget.onSignOut,
              onTabSelected: (index) {
                setState(() => _selectedIndex = index);
              },
            ),
            NavigationScreen(
              onParkingConfirmed: () => setState(() => _parkingRevision++),
              routeRepository: widget.routeRepository,
              isVisible: _selectedIndex == 1,
            ),
            VehiclesScreen(
              vehicleRepository: widget.vehicleRepository,
              isVisible: _selectedIndex == 2,
            ),
            HistoryScreen(
              historyRepository: widget.historyRepository,
              isVisible: _selectedIndex == 3,
            ),
            AccountScreen(
              profile: widget.profile,
              passwordChange: widget.passwordChange,
              onSignOut: widget.onSignOut,
              onVehiclesSelected: () {
                setState(() => _selectedIndex = 2);
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          DriverBottomNavigation(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
          ),
        ],
      ),
    );
  }
}
