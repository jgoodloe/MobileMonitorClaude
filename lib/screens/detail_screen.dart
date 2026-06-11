import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/monitor_status.dart';
import '../services/dns_resolver.dart';
import '../utils/formatters.dart';

/// Read-only detail view for a monitored item. For DNS items it can run an
/// on-demand ping of the resolved addresses.
class DetailScreen extends StatefulWidget {
  final MonitorItem item;

  const DetailScreen({super.key, required this.item});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late MonitorItem _item = widget.item;
  bool _pinging = false;

  Future<void> _pingDns() async {
    setState(() => _pinging = true);
    final updated =
        await const DnsResolver().checkDnsHost(_item.name, pingIps: true);
    if (mounted) {
      setState(() {
        _item = updated;
        _pinging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      appBar: AppBar(title: Text(_typeLabel(item.type))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Overview',
            rows: [
              _Row('Name', item.name, copyable: true),
              _Row('Type', _typeLabel(item.type)),
              _Row('Status', item.status.name.toUpperCase()),
              if (item.lastCheckTime != null)
                _Row('Last check', Formatters.dateTime(item.lastCheckTime!)),
              if (item.responseTime != null)
                _Row('Response time', '${item.responseTime!.inMilliseconds} ms'),
              if (item.errorMessage != null)
                _Row('Error', item.errorMessage!),
            ],
          ),
          if (item.urlErrorDetails != null)
            _Section(
              title: 'Error Details',
              rows: [
                if (item.urlErrorDetails!.errorType != null)
                  _Row('Type', item.urlErrorDetails!.errorType!),
                if (item.urlErrorDetails!.httpStatusCode != null)
                  _Row('HTTP status',
                      '${item.urlErrorDetails!.httpStatusCode}'),
                if (item.urlErrorDetails!.isSslError == true)
                  _Row('SSL error',
                      item.urlErrorDetails!.sslErrorMessage ?? 'Yes'),
              ],
            ),
          if (item.certificateInfo != null)
            _Section(
              title: 'Certificate',
              rows: [
                if (item.certificateInfo!.subject != null)
                  _Row('Subject', item.certificateInfo!.subject!),
                if (item.certificateInfo!.issuer != null)
                  _Row('Issuer', item.certificateInfo!.issuer!),
                if (item.certificateInfo!.validFrom != null)
                  _Row('Valid from',
                      Formatters.date(item.certificateInfo!.validFrom!)),
                if (item.certificateInfo!.validTo != null)
                  _Row('Valid to',
                      Formatters.date(item.certificateInfo!.validTo!)),
                if (item.certificateInfo!.isExpiringSoon)
                  const _Row('Warning', 'Expiring within 30 days'),
              ],
            ),
          if (item.crlValidityInfo != null)
            _Section(
              title: 'CRL',
              rows: [
                if (item.crlValidityInfo!.certificateAuthority != null)
                  _Row('CA', item.crlValidityInfo!.certificateAuthority!),
                if (item.crlValidityInfo!.crlNumber != null)
                  _Row('CRL number', item.crlValidityInfo!.crlNumber!),
                if (item.crlValidityInfo!.revokedCertificateCount != null)
                  _Row('Revoked certs',
                      '${item.crlValidityInfo!.revokedCertificateCount}'),
                if (item.crlValidityInfo!.validFrom != null)
                  _Row('This update',
                      Formatters.dateTime(item.crlValidityInfo!.validFrom!)),
                if (item.crlValidityInfo!.validTo != null)
                  _Row('Next update',
                      Formatters.dateTime(item.crlValidityInfo!.validTo!)),
                if (item.crlValidityInfo!.timeUntilInvalid != null)
                  _Row('Time remaining',
                      Formatters.duration(item.crlValidityInfo!.timeUntilInvalid!)),
              ],
            ),
          if (item.type == MonitorType.dns) _buildDnsSection(item),
          if (item.crlValidityInfo?.parsingLogs.isNotEmpty ?? false)
            _Section(
              title: 'Parsing Logs',
              rows: item.crlValidityInfo!.parsingLogs
                  .map((l) => _Row('•', l))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildDnsSection(MonitorItem item) {
    return _Section(
      title: 'Resolved Addresses',
      trailing: TextButton.icon(
        onPressed: _pinging ? null : _pingDns,
        icon: _pinging
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.network_ping, size: 18),
        label: const Text('Ping'),
      ),
      rows: [
        if (item.ipAddresses == null || item.ipAddresses!.isEmpty)
          const _Row('', 'No addresses')
        else
          for (final ip in item.ipAddresses!)
            _Row(
              ip.ipAddress,
              ip.isPingable
                  ? 'reachable${ip.pingTime != null ? ' (${ip.pingTime!.inMilliseconds} ms)' : ''}'
                  : (ip.pingError ?? 'not pinged'),
            ),
      ],
    );
  }

  String _typeLabel(MonitorType type) => switch (type) {
        MonitorType.url => 'URL',
        MonitorType.dns => 'DNS Host',
        MonitorType.crl => 'CRL',
      };
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  final Widget? trailing;

  const _Section({required this.title, required this.rows, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (trailing != null) trailing!,
              ],
            ),
            const Divider(),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;

  const _Row(this.label, this.value, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: SelectableText(value)),
          if (copyable)
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: value)),
            ),
        ],
      ),
    );
  }
}
