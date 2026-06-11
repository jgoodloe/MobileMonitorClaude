import 'dart:async';
import 'dart:io';

import '../models/monitor_status.dart';
import '../utils/app_config.dart';
import 'ping_service.dart';

class DnsResolver {
  final PingService _pingService;

  const DnsResolver({PingService pingService = const PingService()})
      : _pingService = pingService;

  Future<MonitorItem> checkDnsHost(String hostname,
      {bool pingIps = false}) async {
    try {
      final addresses = await InternetAddress.lookup(hostname)
          .timeout(AppConfig.dnsLookupTimeout,
              onTimeout: () => const <InternetAddress>[]);

      if (addresses.isEmpty) {
        return _down(hostname, 'No addresses found');
      }

      List<IpAddressInfo> ipInfos;
      if (pingIps) {
        ipInfos = await Future.wait(addresses.map((addr) async {
          final time = await _pingService.pingWithTime(addr.address);
          return IpAddressInfo(
            ipAddress: addr.address,
            isPingable: time != null,
            pingTime: time,
            pingError: time == null ? 'Connection failed' : null,
          );
        }));
      } else {
        ipInfos = addresses
            .map((a) => IpAddressInfo(ipAddress: a.address))
            .toList(growable: false);
      }

      return MonitorItem(
        id: hostname,
        name: hostname,
        type: MonitorType.dns,
        status: MonitorStatus.up,
        lastCheckTime: DateTime.now(),
        ipAddresses: ipInfos,
      );
    } on SocketException catch (e) {
      return _down(hostname, e.message);
    } catch (e) {
      return _down(hostname, e.toString());
    }
  }

  MonitorItem _down(String hostname, String message) => MonitorItem(
        id: hostname,
        name: hostname,
        type: MonitorType.dns,
        status: MonitorStatus.down,
        lastCheckTime: DateTime.now(),
        errorMessage: message,
      );
}
