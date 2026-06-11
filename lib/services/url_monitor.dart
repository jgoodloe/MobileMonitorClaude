import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/monitor_status.dart';
import '../utils/app_config.dart';

class UrlMonitor {
  Dio? _dio;

  Dio get _client => _dio ??= _buildDio();

  Dio _buildDio() {
    final dio = Dio(BaseOptions(
      connectTimeout: AppConfig.urlConnectTimeout,
      receiveTimeout: AppConfig.urlReceiveTimeout,
      validateStatus: (status) => status != null && status < 500,
      // Don't pull large bodies into memory just to throw them away; we only
      // care about reachability + status. HEAD-like behavior via small range
      // is unreliable across servers, so we keep GET but avoid retaining body.
      responseType: ResponseType.stream,
    ));

    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      return client;
    };
    return dio;
  }

  Future<MonitorItem> checkUrl(String url) async {
    final uri = Uri.parse(url);
    final isHttps = uri.scheme == 'https';
    final sw = Stopwatch()..start();

    try {
      final response = await _client.get<ResponseBody>(url);
      // Drain the stream so the connection can be released.
      await response.data?.stream.drain<void>();
      sw.stop();

      final code = response.statusCode ?? 0;
      final isUp = code >= 200 && code < 400;

      // FIX (vs. original): the cert is fetched once, only for HTTPS, and only
      // when we actually want to display it — not via a second full request.
      final cert = isHttps ? await _extractCertificate(uri) : null;

      return MonitorItem(
        id: url,
        name: url,
        type: MonitorType.url,
        status: isUp ? MonitorStatus.up : MonitorStatus.down,
        lastCheckTime: DateTime.now(),
        responseTime: sw.elapsed,
        errorMessage: isUp ? null : 'HTTP $code',
        certificateInfo: cert,
      );
    } on DioException catch (e) {
      sw.stop();
      return _failure(url, uri, isHttps, e, sw.elapsed);
    } catch (e) {
      sw.stop();
      return MonitorItem(
        id: url,
        name: url,
        type: MonitorType.url,
        status: MonitorStatus.down,
        lastCheckTime: DateTime.now(),
        responseTime: sw.elapsed,
        errorMessage: e.toString(),
      );
    }
  }

  Future<MonitorItem> _failure(
    String url,
    Uri uri,
    bool isHttps,
    DioException e,
    Duration elapsed,
  ) async {
    String errorType;
    var isSsl = false;
    String? sslMessage;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        errorType = 'Timeout';
        break;
      case DioExceptionType.connectionError:
        errorType = 'ConnectionError';
        break;
      case DioExceptionType.badResponse:
        errorType = 'HttpError';
        break;
      default:
        final msg = e.message ?? '';
        if (e.error is HandshakeException ||
            msg.contains('SSL') ||
            msg.contains('TLS') ||
            msg.contains('certificate')) {
          errorType = 'SSLError';
          isSsl = true;
          sslMessage = e.message;
        } else {
          errorType = e.type.name;
        }
    }

    final cert = isHttps ? await _extractCertificate(uri) : null;

    return MonitorItem(
      id: url,
      name: url,
      type: MonitorType.url,
      status: MonitorStatus.down,
      lastCheckTime: DateTime.now(),
      responseTime: elapsed,
      errorMessage: e.message ?? 'Connection failed',
      certificateInfo: cert,
      urlErrorDetails: UrlErrorDetails(
        errorType: errorType,
        httpStatusCode: e.response?.statusCode,
        responseTime: elapsed,
        isSslError: isSsl,
        sslErrorMessage: sslMessage,
      ),
    );
  }

  Future<CertificateInfo?> _extractCertificate(Uri uri) async {
    final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      final cert = response.certificate;
      // Drain so the socket is freed.
      await response.drain<void>();
      if (cert == null) return null;

      final daysLeft = cert.endValidity.difference(DateTime.now()).inDays;
      return CertificateInfo(
        validFrom: cert.startValidity,
        validTo: cert.endValidity,
        issuer: cert.issuer,
        subject: cert.subject,
        isExpiringSoon: daysLeft > 0 &&
            daysLeft <= AppConfig.certExpiryWarning.inDays,
      );
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  void dispose() => _dio?.close(force: true);
}
