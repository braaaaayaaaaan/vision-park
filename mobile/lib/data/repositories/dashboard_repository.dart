import '../models/dashboard_models.dart';

/// Future UI data contract, not a claim that a dashboard endpoint exists.
///
/// An adapter may compose authenticated reads once backend contracts exist.
/// Counts, tenant quotas and occupancy must be supplied authoritatively.
/// A failed session read must throw, never masquerade as a null active session.
/// No implementation is connected to the application yet.
abstract interface class DashboardRepository {
  Future<DashboardData> getDashboard();
}
