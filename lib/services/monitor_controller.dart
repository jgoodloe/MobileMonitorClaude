import 'package:flutter/foundation.dart';

import '../models/monitor_status.dart';
import '../utils/app_config.dart';
import 'configuration_manager.dart';
import 'crl_verifier.dart';
import 'dns_resolver.dart';
import 'url_monitor.dart';

/// Owns all monitoring state and orchestration, decoupled from the widget tree.
///
/// Improvements over the original (which drove everything from
/// `setState` inside the screen):
///   * URL, DNS, and CRL groups run concurrently instead of one big sequential
///     pass, cutting wall-clock refresh time roughly to the slowest group.
///   * Each item updates independently, so the three tabs fill in live.
///   * No artificial `Future.delayed(Duration.zero)` UI-yield hacks — heavy CRL
///     parsing already runs in an isolate, so the UI thread stays free.
class MonitorController extends ChangeNotifier {
  final ConfigurationManager _config;
  final UrlMonitor _urlMonitor;
  final DnsResolver _dnsResolver;
  final CrlVerifier _crlVerifier;

  MonitorController({
    ConfigurationManager? config,
    UrlMonitor? urlMonitor,
    DnsResolver? dnsResolver,
    CrlVerifier? crlVerifier,
  })  : _config = config ?? ConfigurationManager(),
        _urlMonitor = urlMonitor ?? UrlMonitor(),
        _dnsResolver = dnsResolver ?? const DnsResolver(),
        _crlVerifier = crlVerifier ?? CrlVerifier();

  final List<MonitorItem> _urlItems = [];
  final List<MonitorItem> _dnsItems = [];
  final List<MonitorItem> _crlItems = [];
  bool _isRefreshing = false;

  List<MonitorItem> get urlItems => List.unmodifiable(_urlItems);
  List<MonitorItem> get dnsItems => List.unmodifiable(_dnsItems);
  List<MonitorItem> get crlItems => List.unmodifiable(_crlItems);
  bool get isRefreshing => _isRefreshing;

  bool get hasAnyItems =>
      _urlItems.isNotEmpty || _dnsItems.isNotEmpty || _crlItems.isNotEmpty;

  Future<void> refresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      final config = await _config.load();

      _seed(_urlItems, config.urls, MonitorType.url);
      _seed(_dnsItems, config.dnsHosts, MonitorType.dns);
      _seed(_crlItems, config.crlUrls, MonitorType.crl);
      notifyListeners();

      // Run the three groups concurrently. Within a group, items run in
      // parallel too; the CRL group keeps a light retry for transient errors.
      await Future.wait([
        _runGroup(
          config.urls,
          _urlItems,
          (url) => _urlMonitor.checkUrl(url),
        ),
        _runGroup(
          config.dnsHosts,
          _dnsItems,
          (host) => _dnsResolver.checkDnsHost(host, pingIps: false),
        ),
        _runGroup(
          config.crlUrls,
          _crlItems,
          (url) => _verifyCrlWithRetry(
            url,
            config.countRevokedCertificates,
          ),
        ),
      ]);
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  void _seed(List<MonitorItem> target, List<String> names, MonitorType type) {
    target
      ..clear()
      ..addAll(names.map((n) => MonitorItem(
            id: n,
            name: n,
            type: type,
            status: MonitorStatus.checking,
          )));
  }

  Future<void> _runGroup(
    List<String> names,
    List<MonitorItem> target,
    Future<MonitorItem> Function(String) check,
  ) async {
    await Future.wait(List.generate(names.length, (i) async {
      try {
        final result = await check(names[i]);
        if (i < target.length) {
          target[i] = result;
          notifyListeners();
        }
      } catch (_) {
        if (i < target.length) {
          target[i] = target[i].copyWith(
            status: MonitorStatus.down,
            lastCheckTime: DateTime.now(),
            errorMessage: 'Check failed',
          );
          notifyListeners();
        }
      }
    }));
  }

  Future<MonitorItem> _verifyCrlWithRetry(String url, bool countRevoked) async {
    var result =
        await _crlVerifier.verifyCrl(url, countRevoked: countRevoked);
    var retries = AppConfig.crlMaxRetries;

    while (retries > 0 && _isTransientFailure(result)) {
      retries--;
      await Future.delayed(AppConfig.crlRetryBackoff);
      result = await _crlVerifier.verifyCrl(url, countRevoked: countRevoked);
    }
    return result;
  }

  bool _isTransientFailure(MonitorItem item) {
    if (item.status != MonitorStatus.down || item.errorMessage == null) {
      return false;
    }
    final msg = item.errorMessage!.toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('failed');
  }

  @override
  void dispose() {
    _urlMonitor.dispose();
    _crlVerifier.dispose();
    super.dispose();
  }
}
