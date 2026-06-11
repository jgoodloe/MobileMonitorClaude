import 'package:flutter/material.dart';

import '../models/monitor_status.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// A single monitored item row. Extracted from the screen so each card is its
/// own widget — cheaper rebuilds and reusable across tabs.
class MonitorItemCard extends StatelessWidget {
  final MonitorItem item;
  final VoidCallback onTap;

  const MonitorItemCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final up = switch (item.status) {
      MonitorStatus.up => true,
      MonitorStatus.down => false,
      _ => null,
    };
    final color = StatusColors.forStatus(context, up);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: _StatusAvatar(status: item.status, color: color),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _Subtitle(item: item, theme: theme),
        trailing: const Icon(Icons.chevron_right),
        isThreeLine: item.errorMessage != null ||
            item.certificateInfo != null ||
            item.crlValidityInfo != null,
        onTap: onTap,
      ),
    );
  }
}

class _StatusAvatar extends StatelessWidget {
  final MonitorStatus status;
  final Color color;

  const _StatusAvatar({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    if (status == MonitorStatus.checking) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final icon = switch (status) {
      MonitorStatus.up => Icons.check_circle,
      MonitorStatus.down => Icons.error,
      _ => Icons.help_outline,
    };
    return CircleAvatar(
      backgroundColor: color,
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _Subtitle extends StatelessWidget {
  final MonitorItem item;
  final ThemeData theme;

  const _Subtitle({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (item.errorMessage != null) {
      children.add(Text(
        item.errorMessage!,
        style: TextStyle(color: theme.colorScheme.error),
      ));
    }

    if (item.responseTime != null && item.status == MonitorStatus.up) {
      children.add(Text(
        '${item.responseTime!.inMilliseconds} ms',
        style: theme.textTheme.bodySmall,
      ));
    }

    if (item.lastCheckTime != null) {
      children.add(Text(
        'Last check: ${Formatters.time(item.lastCheckTime!)}',
        style: theme.textTheme.bodySmall,
      ));
    }

    final cert = item.certificateInfo;
    if (cert?.validTo != null) {
      children.add(_ExpiryLine(
        label: 'Cert expires',
        date: cert!.validTo!,
        warn: cert.isExpiringSoon,
        warnText: '⚠ Certificate expiring within 30 days',
      ));
    }

    final crl = item.crlValidityInfo;
    if (crl?.validTo != null) {
      children.add(_ExpiryLine(
        label: 'CRL expires',
        date: crl!.validTo!,
        warn: crl.isExpiringSoon,
        warnText: '⚠ CRL expiring within 1 hour',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ExpiryLine extends StatelessWidget {
  final String label;
  final DateTime date;
  final bool warn;
  final String warnText;

  const _ExpiryLine({
    required this.label,
    required this.date,
    required this.warn,
    required this.warnText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          '$label: ${Formatters.date(date)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: warn ? Colors.orange.shade800 : null,
          ),
        ),
        if (warn)
          Container(
            padding: const EdgeInsets.all(4),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              warnText,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
      ],
    );
  }
}
