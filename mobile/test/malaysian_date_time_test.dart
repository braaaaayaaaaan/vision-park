import 'package:flutter_test/flutter_test.dart';
import 'package:visionpark_mobile/shared/formatting/malaysian_date_time.dart';

void main() {
  test('uses Kuala Lumpur time across a year boundary', () {
    expect(
      MalaysianDateTime.format(DateTime.utc(2026, 12, 31, 18, 5)),
      '01 Jan 2027, 02:05 MYT',
    );
    expect(MalaysianDateTime.timeZone, 'Asia/Kuala_Lumpur');
  });

  test('preserves the instant from an explicit timezone offset', () {
    expect(
      MalaysianDateTime.format(DateTime.parse('2026-10-16T09:30:00+08:00')),
      '16 Oct 2026, 09:30 MYT',
    );
  });

  test('does not silently apply modern rules to historical dates', () {
    expect(
      () => MalaysianDateTime.format(DateTime.utc(1980)),
      throwsArgumentError,
    );
  });
}
