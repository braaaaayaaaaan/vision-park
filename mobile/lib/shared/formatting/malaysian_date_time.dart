import '../../app/app_config.dart';

/// British English, 24-hour display in Asia/Kuala_Lumpur, not device time.
///
/// Kuala Lumpur has used UTC+08:00 without daylight saving since 1982.
/// This lightweight formatter covers modern parking records only. Historical
/// dates before that transition require an IANA timezone implementation.
abstract final class MalaysianDateTime {
  static const timeZone = AppConfig.timeZone;
  static const _offset = Duration(hours: 8);
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String format(DateTime instant) {
    final utc = instant.toUtc();
    if (utc.isBefore(DateTime.utc(1981, 12, 31, 16))) {
      throw ArgumentError.value(
        instant,
        'instant',
        'Requires a date in 1982 or later',
      );
    }

    final local = utc.add(_offset);
    final day = _twoDigits(local.day);
    final month = _months[local.month - 1];
    final hour = _twoDigits(local.hour);
    final minute = _twoDigits(local.minute);

    return '$day $month ${local.year}, $hour:$minute MYT';
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
