import 'package:shared_preferences/shared_preferences.dart';

/// Immutable snapshot of all monitoring configuration.
class MonitorConfig {
  final List<String> urls;
  final List<String> dnsHosts;
  final List<String> crlUrls;
  final bool countRevokedCertificates;

  const MonitorConfig({
    required this.urls,
    required this.dnsHosts,
    required this.crlUrls,
    required this.countRevokedCertificates,
  });
}

class ConfigurationManager {
  static const String _urlsKey = 'monitor_urls';
  static const String _dnsHostsKey = 'monitor_dns_hosts';
  static const String _crlUrlsKey = 'monitor_crl_urls';
  static const String _countRevokedKey = 'monitor_count_revoked_certificates';

  static const List<String> defaultUrls = [
    'https://pivi.xcloud.authentx.com/portal/index.html',
    'https://piv.xcloud.authentx.com/portal/index.html',
  ];

  static const List<String> defaultDnsHosts = [
    'piv.xcloud.authentx.com',
    'pivi.xcloud.authentx.com',
    'ocsp.xca.xpki.com',
    'crl.xca.xpki.com',
    'aia.xca.xpki.com',
  ];

  static const List<String> defaultCrlUrls = [
    'http://crl.xca.xpki.com/CRLs/XTec_PIVI_CA1.crl',
    'http://66.165.167.225/CRLs/XTec_PIVI_CA1.crl',
    'http://152.186.38.46/CRLs/XTec_PIVI_CA1.crl',
  ];

  static SharedPreferences? _prefs;
  static Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Loads the full configuration in a single await rather than the three
  /// sequential round-trips the original used in its hot refresh path.
  Future<MonitorConfig> load() async {
    final prefs = await _getPrefs();
    return MonitorConfig(
      urls: prefs.getStringList(_urlsKey) ?? defaultUrls,
      dnsHosts: prefs.getStringList(_dnsHostsKey) ?? defaultDnsHosts,
      crlUrls: prefs.getStringList(_crlUrlsKey) ?? defaultCrlUrls,
      countRevokedCertificates: prefs.getBool(_countRevokedKey) ?? true,
    );
  }

  Future<void> setUrls(List<String> urls) async =>
      (await _getPrefs()).setStringList(_urlsKey, urls);

  Future<void> setDnsHosts(List<String> hosts) async =>
      (await _getPrefs()).setStringList(_dnsHostsKey, hosts);

  Future<void> setCrlUrls(List<String> urls) async =>
      (await _getPrefs()).setStringList(_crlUrlsKey, urls);

  Future<void> setCountRevokedCertificates(bool value) async =>
      (await _getPrefs()).setBool(_countRevokedKey, value);

  Future<void> resetToDefaults() async {
    await setUrls(defaultUrls);
    await setDnsHosts(defaultDnsHosts);
    await setCrlUrls(defaultCrlUrls);
    await setCountRevokedCertificates(true);
  }
}
