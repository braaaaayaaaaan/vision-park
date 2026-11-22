import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../app/app_config.dart';
import '../../data/models/driver_models.dart';

/// Device-local cooldowns for a single authenticated driver.
class ParkingReminderSchedule {
  ParkingReminderSchedule(String owner, this._clock)
    : _key = 'vp_parking_reminder_v1:$owner';

  final String _key;
  final DateTime Function() _clock;
  final _snoozedUntil = <String, int>{};
  final _confirmed = <String>{};
  SharedPreferences? _preferences;
  bool ready = false;

  Future<void> restore() async {
    try {
      final preferences = _preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString(_key);
      if (saved == null) return;
      final decoded = jsonDecode(saved);
      if (decoded is! Map<String, dynamic>) return;
      final now = _clock().millisecondsSinceEpoch;
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (value is int && value > now) _snoozedUntil[key] = value;
      }
    } catch (_) {
      // Cooldowns still work in memory if local storage is unavailable.
    } finally {
      ready = true;
    }
  }

  bool isDue(ParkingSession session) {
    final now = _clock();
    return !_confirmed.contains(session.id) &&
        !now.isBefore(session.entryTime.add(AppConfig.parkingReminderDelay)) &&
        (_snoozedUntil[session.id] ?? 0) <= now.millisecondsSinceEpoch;
  }

  void markConfirmed(String sessionId) => _confirmed.add(sessionId);

  void snooze(String sessionId) {
    final now = _clock();
    _snoozedUntil.removeWhere(
      (_, until) => until <= now.millisecondsSinceEpoch,
    );
    _snoozedUntil[sessionId] = now
        .add(AppConfig.parkingReminderSnooze)
        .millisecondsSinceEpoch;
    unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await _preferences?.setString(_key, jsonEncode(_snoozedUntil));
    } catch (_) {
      // The current shell still retains the cooldown.
    }
  }
}
