import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_monitor_claude/models/monitor_status.dart';

void main() {
  group('MonitorItem JSON round-trip', () {
    test('preserves all fields including responseTime', () {
      final item = MonitorItem(
        id: 'https://example.com',
        name: 'https://example.com',
        type: MonitorType.url,
        status: MonitorStatus.up,
        lastCheckTime: DateTime.utc(2026, 1, 1, 12, 0, 0),
        responseTime: const Duration(milliseconds: 250),
        certificateInfo: CertificateInfo(
          validFrom: DateTime.utc(2025, 1, 1),
          validTo: DateTime.utc(2026, 6, 1),
          issuer: 'Test CA',
          subject: 'example.com',
          isExpiringSoon: true,
        ),
      );

      final restored = MonitorItem.fromJson(item.toJson());

      expect(restored.id, item.id);
      expect(restored.status, MonitorStatus.up);
      expect(restored.responseTime, const Duration(milliseconds: 250));
      expect(restored.certificateInfo?.issuer, 'Test CA');
      expect(restored.certificateInfo?.isExpiringSoon, isTrue);
    });

    test('reads legacy enum.toString() format', () {
      final legacy = {
        'id': 'h',
        'name': 'h',
        'type': 'MonitorType.dns',
        'status': 'MonitorStatus.down',
      };
      final item = MonitorItem.fromJson(legacy);
      expect(item.type, MonitorType.dns);
      expect(item.status, MonitorStatus.down);
    });
  });

  group('CrlValidityInfo JSON', () {
    test('round-trips timeUntilInvalid and parsingLogs (regression)', () {
      const info = CrlValidityInfo(
        timeUntilInvalid: Duration(hours: 5),
        parsingLogs: ['line one', 'line two'],
        crlNumber: '42',
      );
      final restored = CrlValidityInfo.fromJson(info.toJson());
      // Original code dropped these two fields on deserialization.
      expect(restored.timeUntilInvalid, const Duration(hours: 5));
      expect(restored.parsingLogs, ['line one', 'line two']);
      expect(restored.crlNumber, '42');
    });
  });
}
