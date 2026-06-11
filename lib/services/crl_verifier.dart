import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/monitor_status.dart';
import '../utils/app_config.dart';
import '../utils/logging.dart';
import 'crl_parser.dart';

final _log = appLogger('CrlVerifier');

class CrlVerifier {
  Dio? _dio;

  Dio get _client => _dio ??= Dio(BaseOptions(
        connectTimeout: AppConfig.crlConnectTimeout,
        receiveTimeout: AppConfig.crlReceiveTimeout,
        validateStatus: (s) => s != null && s < 500,
        responseType: ResponseType.bytes,
      ));

  Future<MonitorItem> verifyCrl(String crlUrl, {bool countRevoked = true}) async {
    try {
      final response = await _client.get<List<int>>(crlUrl);
      final code = response.statusCode ?? 0;
      if (code >= 400) {
        return _down(crlUrl, 'HTTP $code');
      }

      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) return _down(crlUrl, 'Empty CRL file');
      if (bytes.length > AppConfig.maxCrlBytes) {
        return _down(crlUrl, 'CRL too large (${bytes.length} bytes)');
      }

      // Heavy ASN.1 parsing runs off the UI thread.
      final parsed = await compute(parseCrlIsolate, <String, dynamic>{
        'crlBytes': bytes,
        'countRevoked': countRevoked,
      });

      final logs = (parsed['parsingLogs'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];

      var ca = parsed['issuer'] as String?;
      ca ??= _caFromUrl(crlUrl);

      final validFrom = _tryDate(parsed['thisUpdate'] as String?);
      final validTo = _tryDate(parsed['nextUpdate'] as String?);

      Duration? timeUntilInvalid;
      var expiringSoon = false;
      if (validTo != null) {
        timeUntilInvalid = validTo.difference(DateTime.now());
        expiringSoon = !timeUntilInvalid.isNegative &&
            timeUntilInvalid <= AppConfig.crlExpiryWarning;
      }

      final validity = CrlValidityInfo(
        validFrom: validFrom,
        validTo: validTo,
        timeUntilInvalid: (timeUntilInvalid?.isNegative ?? false)
            ? Duration.zero
            : timeUntilInvalid,
        isExpiringSoon: expiringSoon,
        revokedCertificateCount: parsed['revokedCount'] as int?,
        certificateAuthority: ca,
        crlNumber: parsed['crlNumber'] as String?,
        parsingLogs: logs,
      );

      return MonitorItem(
        id: crlUrl,
        name: crlUrl,
        type: MonitorType.crl,
        status: MonitorStatus.up,
        lastCheckTime: DateTime.now(),
        crlValidityInfo: validity,
      );
    } on DioException catch (e) {
      _log.warning('CRL fetch failed for $crlUrl: ${e.message}');
      return _down(crlUrl, e.message ?? 'Connection failed');
    } catch (e) {
      _log.warning('CRL error for $crlUrl: $e');
      return _down(crlUrl, e.toString());
    }
  }

  /// Derives a human-readable CA when the CRL issuer DN can't be parsed,
  /// preferring hostname, then filename (with known-pattern enrichment).
  static String? _caFromUrl(String crlUrl) {
    final uri = Uri.tryParse(crlUrl);
    if (uri == null) return null;

    if (uri.host.isNotEmpty && !_isIpAddress(uri.host)) {
      return uri.host;
    }

    for (final segment in uri.pathSegments.reversed) {
      if (segment.toLowerCase().endsWith('.crl')) {
        final base = segment.substring(0, segment.length - 4);
        if (base.contains('XTec') || base.contains('Xtec')) {
          if (base.contains('WidePoint') || base.contains('PIVI')) {
            return 'XTec Incorporated / WidePoint';
          }
          return 'XTec Incorporated';
        }
        if (base.contains('WidePoint')) return 'WidePoint';
        return base.replaceAll('_', ' ');
      }
    }
    return null;
  }

  static bool _isIpAddress(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static DateTime? _tryDate(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw);

  MonitorItem _down(String url, String message) => MonitorItem(
        id: url,
        name: url,
        type: MonitorType.crl,
        status: MonitorStatus.down,
        lastCheckTime: DateTime.now(),
        errorMessage: message,
      );

  void dispose() => _dio?.close(force: true);
}
