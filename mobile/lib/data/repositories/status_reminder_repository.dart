import 'auth_repository.dart';

class ParkingStatusReminder {
  const ParkingStatusReminder({
    required this.id,
    required this.sessionId,
    required this.plateNumber,
    required this.message,
    required this.sentAt,
  });
  final String id, sessionId, plateNumber, message;
  final DateTime sentAt;

  factory ParkingStatusReminder.fromJson(dynamic value) {
    final row = value as Map<String, dynamic>;
    String text(String key) {
      final text = row[key] as String;
      if (text.trim().isEmpty) throw const FormatException();
      return text;
    }

    final sentAt = DateTime.parse(text('sent_at'));
    if (!sentAt.isUtc ||
        row['response'] != null ||
        row['responded_at'] != null) {
      throw const FormatException();
    }
    return ParkingStatusReminder(
      id: text('id'),
      sessionId: text('session_id'),
      plateNumber: text('plate_number'),
      message: text('message'),
      sentAt: sentAt,
    );
  }
}

abstract interface class StatusReminderRepository {
  Future<List<ParkingStatusReminder>> getReminders();
  Future<void> respond(String id, String response);
}

class RemoteStatusReminderRepository implements StatusReminderRepository {
  RemoteStatusReminderRepository(this.api);
  final RemoteAuthRepository api;
  @override
  Future<List<ParkingStatusReminder>> getReminders() async {
    final data = await api.getAuthenticated('parking/status-reminders');
    try {
      final rows = (data as Map<String, dynamic>)['reminders'] as List;
      final reminders = rows.map(ParkingStatusReminder.fromJson).toList();
      if (reminders.map((row) => row.sessionId).toSet().length !=
          reminders.length) {
        throw const FormatException();
      }
      return List.unmodifiable(reminders);
    } catch (_) {
      throw const AuthFailure(
        'Unable to read parking reminders. Please retry.',
      );
    }
  }

  @override
  Future<void> respond(String id, String response) async {
    if (!['still_parked', 'already_left'].contains(response)) {
      throw const AuthFailure('Choose a valid parking response.');
    }
    final data = await api.postAuthenticated(
      'parking/status-reminders/${Uri.encodeComponent(id)}/response',
      body: {'response': response},
    );
    if (data is! Map || data['status'] != 'recorded') {
      throw const AuthFailure(
        'Your response could not be confirmed. Please retry.',
      );
    }
  }
}
