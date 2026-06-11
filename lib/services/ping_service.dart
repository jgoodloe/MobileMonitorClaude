import 'dart:async';
import 'dart:io';

import '../utils/app_config.dart';

/// Lightweight reachability check via TCP connect. Not ICMP (which mobile
/// sandboxes disallow), so this confirms a port is accepting connections.
class PingService {
  const PingService();

  Future<bool> ping(String ip, {Duration? timeout}) async =>
      (await pingWithTime(ip, timeout: timeout)) != null;

  /// Returns the connect latency to the first reachable port, or null.
  ///
  /// FIX (vs. original): the original reset the stopwatch before the 443
  /// attempt but never started it again, so a successful HTTPS-only host
  /// reported a near-zero (wrong) ping time. Here each attempt is timed
  /// independently with a fresh stopwatch.
  Future<Duration?> pingWithTime(String ip, {Duration? timeout}) async {
    final t = timeout ?? AppConfig.pingTimeout;
    for (final port in AppConfig.pingPorts) {
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(ip, port, timeout: t).timeout(t);
        sw.stop();
        await socket.close();
        return sw.elapsed;
      } catch (_) {
        // Try next port.
      }
    }
    return null;
  }
}
