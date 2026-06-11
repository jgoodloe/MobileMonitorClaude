import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_monitor_claude/utils/formatters.dart';

void main() {
  group('Formatters.duration', () {
    test('formats days, hours, minutes, seconds', () {
      expect(Formatters.duration(const Duration(days: 2, hours: 3)), '2d 3h');
      expect(Formatters.duration(const Duration(hours: 1, minutes: 30)), '1h 30m');
      expect(Formatters.duration(const Duration(minutes: 5, seconds: 10)), '5m 10s');
      expect(Formatters.duration(const Duration(seconds: 42)), '42s');
    });

    test('negative duration reads as expired', () {
      expect(Formatters.duration(const Duration(seconds: -1)), 'expired');
    });
  });

  group('Formatters.date / time', () {
    test('zero-pads components', () {
      final dt = DateTime(2026, 3, 7, 9, 5, 4);
      expect(Formatters.date(dt), '2026-03-07');
      expect(Formatters.time(dt), '09:05:04');
    });
  });
}
