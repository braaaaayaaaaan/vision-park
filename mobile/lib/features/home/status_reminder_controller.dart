import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/status_reminder_repository.dart';

class StatusReminderController extends ChangeNotifier {
  StatusReminderController(this.repository);
  final StatusReminderRepository repository;
  List<ParkingStatusReminder> reminders = const [];
  String? error, notice;
  bool loading = false, sending = false, _disposed = false;
  int _revision = 0;

  Future<void> load() async {
    if (_disposed || loading || sending) return;
    loading = true;
    final revision = _revision;
    try {
      final result = await repository.getReminders();
      if (_disposed || revision != _revision) return;
      reminders = result;
      error = null;
    } catch (_) {
      if (_disposed || revision != _revision) return;
      reminders = const [];
      error = 'Parking reminders could not be checked. Please retry.';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> respond(ParkingStatusReminder reminder, String response) async {
    if (_disposed || sending) return;
    sending = true;
    _revision++;
    error = null;
    notice = null;
    notifyListeners();
    try {
      await repository.respond(reminder.id, response);
      if (_disposed) return;
      reminders = reminders.where((row) => row.id != reminder.id).toList();
      notice =
          'Thank you. Your parking status has been sent to the administrator.';
    } on AuthFailure catch (failure) {
      if (!_disposed) error = failure.message;
    } catch (_) {
      if (!_disposed) {
        error = 'Your response could not be confirmed. Please retry.';
      }
    } finally {
      sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
