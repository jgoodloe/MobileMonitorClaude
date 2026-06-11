import 'package:flutter/foundation.dart';

/// Operational status of a monitored item.
///
/// [checking] was added in the Claude fork so placeholder rows can show an
/// explicit "in progress" state instead of an ambiguous [unknown].
enum MonitorStatus { up, down, unknown, checking }

enum MonitorType { url, dns, crl }

@immutable
class MonitorItem {
  final String id;
  final String name;
  final MonitorType type;
  final MonitorStatus status;
  final DateTime? lastCheckTime;
  final String? errorMessage;
  final CertificateInfo? certificateInfo;
  final UrlErrorDetails? urlErrorDetails;
  final List<IpAddressInfo>? ipAddresses;
  final CrlValidityInfo? crlValidityInfo;

  /// Round-trip latency of the most recent check, when measured.
  final Duration? responseTime;

  const MonitorItem({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    this.lastCheckTime,
    this.errorMessage,
    this.certificateInfo,
    this.urlErrorDetails,
    this.ipAddresses,
    this.crlValidityInfo,
    this.responseTime,
  });

  MonitorItem copyWith({
    String? id,
    String? name,
    MonitorType? type,
    MonitorStatus? status,
    DateTime? lastCheckTime,
    String? errorMessage,
    CertificateInfo? certificateInfo,
    UrlErrorDetails? urlErrorDetails,
    List<IpAddressInfo>? ipAddresses,
    CrlValidityInfo? crlValidityInfo,
    Duration? responseTime,
  }) {
    return MonitorItem(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      status: status ?? this.status,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
      errorMessage: errorMessage ?? this.errorMessage,
      certificateInfo: certificateInfo ?? this.certificateInfo,
      urlErrorDetails: urlErrorDetails ?? this.urlErrorDetails,
      ipAddresses: ipAddresses ?? this.ipAddresses,
      crlValidityInfo: crlValidityInfo ?? this.crlValidityInfo,
      responseTime: responseTime ?? this.responseTime,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'status': status.name,
        'lastCheckTime': lastCheckTime?.toIso8601String(),
        'errorMessage': errorMessage,
        'certificateInfo': certificateInfo?.toJson(),
        'urlErrorDetails': urlErrorDetails?.toJson(),
        'ipAddresses': ipAddresses?.map((ip) => ip.toJson()).toList(),
        'crlValidityInfo': crlValidityInfo?.toJson(),
        'responseTime': responseTime?.inMilliseconds,
      };

  factory MonitorItem.fromJson(Map<String, dynamic> json) {
    return MonitorItem(
      id: json['id'] as String,
      name: json['name'] as String,
      type: MonitorType.values.byName(_legacyEnumName(json['type'] as String?)),
      status: MonitorStatus.values
          .byName(_legacyEnumName(json['status'] as String?)),
      lastCheckTime: _parseDate(json['lastCheckTime']),
      errorMessage: json['errorMessage'] as String?,
      certificateInfo: json['certificateInfo'] != null
          ? CertificateInfo.fromJson(
              json['certificateInfo'] as Map<String, dynamic>)
          : null,
      urlErrorDetails: json['urlErrorDetails'] != null
          ? UrlErrorDetails.fromJson(
              json['urlErrorDetails'] as Map<String, dynamic>)
          : null,
      ipAddresses: (json['ipAddresses'] as List?)
          ?.map((ip) => IpAddressInfo.fromJson(ip as Map<String, dynamic>))
          .toList(),
      crlValidityInfo: json['crlValidityInfo'] != null
          ? CrlValidityInfo.fromJson(
              json['crlValidityInfo'] as Map<String, dynamic>)
          : null,
      responseTime: json['responseTime'] != null
          ? Duration(milliseconds: json['responseTime'] as int)
          : null,
    );
  }

  /// Accepts both the new `enum.name` form ("url") and the legacy
  /// `enum.toString()` form ("MonitorType.url") written by the original app.
  static String _legacyEnumName(String? raw) {
    if (raw == null) return 'unknown';
    final dot = raw.lastIndexOf('.');
    return dot >= 0 ? raw.substring(dot + 1) : raw;
  }

  @override
  bool operator ==(Object other) =>
      other is MonitorItem &&
      other.id == id &&
      other.status == status &&
      other.lastCheckTime == lastCheckTime &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(id, status, lastCheckTime, errorMessage);
}

@immutable
class CertificateInfo {
  final DateTime? validFrom;
  final DateTime? validTo;
  final String? issuer;
  final String? subject;
  final bool isExpiringSoon;

  const CertificateInfo({
    this.validFrom,
    this.validTo,
    this.issuer,
    this.subject,
    this.isExpiringSoon = false,
  });

  Map<String, dynamic> toJson() => {
        'validFrom': validFrom?.toIso8601String(),
        'validTo': validTo?.toIso8601String(),
        'issuer': issuer,
        'subject': subject,
        'isExpiringSoon': isExpiringSoon,
      };

  factory CertificateInfo.fromJson(Map<String, dynamic> json) =>
      CertificateInfo(
        validFrom: _parseDate(json['validFrom']),
        validTo: _parseDate(json['validTo']),
        issuer: json['issuer'] as String?,
        subject: json['subject'] as String?,
        isExpiringSoon: json['isExpiringSoon'] as bool? ?? false,
      );
}

@immutable
class UrlErrorDetails {
  final String? errorType;
  final int? httpStatusCode;
  final String? responseBody;
  final Duration? responseTime;
  final bool? isSslError;
  final String? sslErrorMessage;

  const UrlErrorDetails({
    this.errorType,
    this.httpStatusCode,
    this.responseBody,
    this.responseTime,
    this.isSslError,
    this.sslErrorMessage,
  });

  Map<String, dynamic> toJson() => {
        'errorType': errorType,
        'httpStatusCode': httpStatusCode,
        'responseBody': responseBody,
        'responseTime': responseTime?.inMilliseconds,
        'isSslError': isSslError,
        'sslErrorMessage': sslErrorMessage,
      };

  factory UrlErrorDetails.fromJson(Map<String, dynamic> json) =>
      UrlErrorDetails(
        errorType: json['errorType'] as String?,
        httpStatusCode: json['httpStatusCode'] as int?,
        responseBody: json['responseBody'] as String?,
        responseTime: json['responseTime'] != null
            ? Duration(milliseconds: json['responseTime'] as int)
            : null,
        isSslError: json['isSslError'] as bool?,
        sslErrorMessage: json['sslErrorMessage'] as String?,
      );
}

@immutable
class IpAddressInfo {
  final String ipAddress;
  final bool isPingable;
  final Duration? pingTime;
  final String? pingError;

  const IpAddressInfo({
    required this.ipAddress,
    this.isPingable = false,
    this.pingTime,
    this.pingError,
  });

  Map<String, dynamic> toJson() => {
        'ipAddress': ipAddress,
        'isPingable': isPingable,
        'pingTime': pingTime?.inMilliseconds,
        'pingError': pingError,
      };

  factory IpAddressInfo.fromJson(Map<String, dynamic> json) => IpAddressInfo(
        ipAddress: json['ipAddress'] as String,
        isPingable: json['isPingable'] as bool? ?? false,
        pingTime: json['pingTime'] != null
            ? Duration(milliseconds: json['pingTime'] as int)
            : null,
        pingError: json['pingError'] as String?,
      );
}

@immutable
class CrlValidityInfo {
  final DateTime? validFrom;
  final DateTime? validTo;
  final Duration? timeUntilInvalid;
  final bool isExpiringSoon;
  final int? revokedCertificateCount;
  final String? certificateAuthority;
  final String? crlNumber;
  final List<String> parsingLogs;

  const CrlValidityInfo({
    this.validFrom,
    this.validTo,
    this.timeUntilInvalid,
    this.isExpiringSoon = false,
    this.revokedCertificateCount,
    this.certificateAuthority,
    this.crlNumber,
    this.parsingLogs = const [],
  });

  Map<String, dynamic> toJson() => {
        'validFrom': validFrom?.toIso8601String(),
        'validTo': validTo?.toIso8601String(),
        'timeUntilInvalid': timeUntilInvalid?.inMilliseconds,
        'isExpiringSoon': isExpiringSoon,
        'revokedCertificateCount': revokedCertificateCount,
        'certificateAuthority': certificateAuthority,
        'crlNumber': crlNumber,
        'parsingLogs': parsingLogs,
      };

  // FIX (vs. original): original fromJson dropped timeUntilInvalid and
  // parsingLogs, so a deserialized CRL lost its countdown and logs.
  factory CrlValidityInfo.fromJson(Map<String, dynamic> json) =>
      CrlValidityInfo(
        validFrom: _parseDate(json['validFrom']),
        validTo: _parseDate(json['validTo']),
        timeUntilInvalid: json['timeUntilInvalid'] != null
            ? Duration(milliseconds: json['timeUntilInvalid'] as int)
            : null,
        isExpiringSoon: json['isExpiringSoon'] as bool? ?? false,
        revokedCertificateCount: json['revokedCertificateCount'] as int?,
        certificateAuthority: json['certificateAuthority'] as String?,
        crlNumber: json['crlNumber'] as String?,
        parsingLogs: (json['parsingLogs'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

DateTime? _parseDate(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}
