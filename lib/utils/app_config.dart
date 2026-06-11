/// Centralized tunables. The original scattered magic numbers (timeouts,
/// the 30-day cert window, the 1-hour CRL window, retry counts) across
/// several files; collecting them here makes behavior auditable and testable.
class AppConfig {
  const AppConfig._();

  // Network timeouts
  static const Duration urlConnectTimeout = Duration(seconds: 10);
  static const Duration urlReceiveTimeout = Duration(seconds: 10);
  static const Duration crlConnectTimeout = Duration(seconds: 15);
  static const Duration crlReceiveTimeout = Duration(seconds: 15);
  static const Duration dnsLookupTimeout = Duration(seconds: 5);
  static const Duration pingTimeout = Duration(seconds: 3);

  // Expiry thresholds
  static const Duration certExpiryWarning = Duration(days: 30);
  static const Duration crlExpiryWarning = Duration(hours: 1);

  // CRL retry policy
  static const int crlMaxRetries = 2;
  static const Duration crlRetryBackoff = Duration(milliseconds: 300);

  // Safety limit on CRL size to keep ASN.1 parsing bounded.
  static const int maxCrlBytes = 10 * 1024 * 1024;

  // Ports tried by the lightweight TCP "ping".
  static const List<int> pingPorts = [443, 80];
}
