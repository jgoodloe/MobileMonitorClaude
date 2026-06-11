import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';

/// CRL ASN.1 parser, isolated from networking and UI.
///
/// This is a faithful port of the original MobileMonitor parser with all
/// ~120 `print()` debug statements removed (they ran on every parse, including
/// release builds). Diagnostic output now flows through the returned
/// `parsingLogs` list, which the detail screen already surfaces.
///
/// Designed to run inside a background isolate via `compute()`.

/// Isolate entry point. Returns a map with optional keys:
/// issuer, revokedCount, crlNumber, thisUpdate, nextUpdate, parsingLogs.
Map<String, dynamic> parseCrlIsolate(Map<String, dynamic> params) {
  final logs = <String>[];
  try {
    final crlBytes = (params['crlBytes'] as List).cast<int>();
    final countRevoked = params['countRevoked'] as bool? ?? true;
    final result =
    parseCrlInternal(crlBytes, countRevoked: countRevoked, logs: logs);
    result['parsingLogs'] = logs;
    return result;
  } catch (e) {
    logs.add('Error parsing CRL: $e');
    return {'parsingLogs': logs};
  }
}

/// Internal CRL parsing logic
Map<String, dynamic> parseCrlInternal(
  List<int> crlBytes, {
    bool countRevoked = true,
    List<String>? logs,
  }) {
  final result = <String, dynamic>{};
  final parsingLogs = logs ?? <String>[];
  parsingLogs.add('Parsing CRL binary data (${crlBytes.length} bytes)');

  try {
    // Limit parsing to reasonable file sizes (max 10MB)
    if (crlBytes.length > 10 * 1024 * 1024) {
      return result;
    }

    // Parse the CRL using ASN1 - convert List<int> to Uint8List
    final bytes = Uint8List.fromList(crlBytes);
    final asn1Parser = ASN1Parser(bytes);
    final topLevelSeq = asn1Parser.nextObject();

    if (topLevelSeq is! ASN1Sequence) {
      return result;
    }

    final seq = topLevelSeq;
    if (seq.elements.isEmpty) {
      return result;
    }

    // CRL structure: CertificateList ::= SEQUENCE {
    //   tbsCertList TBSCertList,
    //   signatureAlgorithm AlgorithmIdentifier,
    //   signatureValue BIT STRING
    // }

    // Get tbsCertList (first element)
    if (seq.elements.isNotEmpty) {
      final firstElement = seq.elements[0];
      if (firstElement is ASN1Sequence) {
        final tbsCertList = firstElement;

        if (tbsCertList.elements.isNotEmpty) {
          // TBSCertList structure: [version], signature, issuer, thisUpdate, nextUpdate, [revokedCertificates], [extensions]
          int elementIndex = 0;

          // Skip version if present (context-specific [0] - check tag value)
          // Version is optional and tagged, but we'll detect it by checking if first element is tagged [0]
          if (tbsCertList.elements.isNotEmpty) {
            final firstElem = tbsCertList.elements[elementIndex];
            // Check if this looks like a version tag (tagged object with tag 0x80 or similar)
            if (firstElem.tag == 0x80 || firstElem.tag == 0xA0) {
              elementIndex++; // Skip version
            }
          }

          // Skip signature algorithm (AlgorithmIdentifier) - it's a Sequence [OID, Parameters]
          if (tbsCertList.elements.length > elementIndex) {
            final sigAlgElement = tbsCertList.elements[elementIndex];
            elementIndex++; // Skip signature
          }

          // Extract issuer (Distinguished Name) - this is a Sequence

          if (tbsCertList.elements.length > elementIndex) {
            final issuerElement = tbsCertList.elements[elementIndex];

            // The issuer DN is a Name type, which is a SEQUENCE OF RelativeDistinguishedName
            // RelativeDistinguishedName is a SET OF AttributeTypeAndValue
            if (issuerElement is ASN1Sequence) {
              // Check if this sequence contains Sets (which would indicate it's the DN)
              final hasSets = issuerElement.elements.any((e) => e is ASN1Set);

              if (hasSets || issuerElement.elements.length > 2) {
                // This looks like a DN structure
                final issuerDn = _parseDistinguishedName(issuerElement);
                if (issuerDn.isNotEmpty) {
                  result['issuer'] = issuerDn;
                  parsingLogs.add('Parsed issuer DN: $issuerDn');
                }
                elementIndex++;
              } else {
                elementIndex++; // Skip and try next element
              }
            } else {
              // Still increment to avoid getting stuck
              elementIndex++;
            }
          } else {
          }

          // Extract thisUpdate (UTCTime or GeneralizedTime)
          if (tbsCertList.elements.length > elementIndex) {
            final thisUpdateElement = tbsCertList.elements[elementIndex];

            // Check if this might actually be the issuer DN (if we didn't find it earlier)
            bool processedIssuerAtThisPosition = false;
            if (thisUpdateElement is ASN1Sequence &&
              result['issuer'] == null) {
              final hasSets = thisUpdateElement.elements.any(
                (e) => e is ASN1Set,
              );
              if (hasSets) {
                final issuerDn = _parseDistinguishedName(thisUpdateElement);
                if (issuerDn.isNotEmpty) {
                  result['issuer'] = issuerDn;
                  parsingLogs.add('Parsed issuer DN: $issuerDn');
                  elementIndex++;
                  processedIssuerAtThisPosition = true;
                  // Continue to next element for actual thisUpdate
                  if (tbsCertList.elements.length > elementIndex) {
                    final actualThisUpdate =
                    tbsCertList.elements[elementIndex];
                    final thisUpdateStr = _parseTime(actualThisUpdate);
                    if (thisUpdateStr != null) {
                      result['thisUpdate'] = thisUpdateStr;
                      parsingLogs.add('Parsed thisUpdate: $thisUpdateStr');
                    }
                    elementIndex++;
                  }
                }
              }
            }

            if (!processedIssuerAtThisPosition) {
              final thisUpdateStr = _parseTime(thisUpdateElement);
              if (thisUpdateStr != null) {
                result['thisUpdate'] = thisUpdateStr;
                parsingLogs.add('Parsed thisUpdate: $thisUpdateStr');
              } else {
              }
              elementIndex++;
            }
          }

          // Extract nextUpdate (UTCTime or GeneralizedTime)
          if (tbsCertList.elements.length > elementIndex) {
            final nextUpdateElement = tbsCertList.elements[elementIndex];
            final nextUpdateStr = _parseTime(nextUpdateElement);
            if (nextUpdateStr != null) {
              result['nextUpdate'] = nextUpdateStr;
              parsingLogs.add('Parsed nextUpdate: $nextUpdateStr');
            } else {
            }
            elementIndex++;
          }

          // Extract revoked certificates (optional) - this is a Sequence of revoked certificates
          if (tbsCertList.elements.length > elementIndex) {
            final revokedCertificates = tbsCertList.elements[elementIndex];
            if (revokedCertificates is ASN1Sequence) {
              if (countRevoked) {
                // Count revoked certificates - each revoked cert is a Sequence
                final revokedCount = revokedCertificates.elements.length;
                result['revokedCount'] = revokedCount;
                parsingLogs.add(
                  'Found $revokedCount revoked certificates in CRL',
                );
              } else {
                parsingLogs.add(
                  'Skipping revoked certificate count (disabled in settings)',
                );
              }
              elementIndex++;
            }
          }

          // Extract extensions (optional) - context-specific [0] EXPLICIT Extensions
          // Check remaining elements for tagged extension (tag 0)
          for (
            int extIdx = elementIndex;
            extIdx < tbsCertList.elements.length;
            extIdx++
          ) {
            final potentialExtElement = tbsCertList.elements[extIdx];

            // Extensions are tagged as [0] EXPLICIT, which means they may be wrapped
            // Check if this is a tagged element with tag 0 (context-specific)
            // Tag 0xA0 = context-specific [0] constructed, tag 0x80 = context-specific [0] primitive
            ASN1Sequence? extensionsSequence;

            // Check for context-specific tag [0] (0xA0 for constructed, 0x80 for primitive)
            final isTaggedZero =
            (potentialExtElement.tag & 0xE0) == 0xA0 ||
            (potentialExtElement.tag & 0xE0) == 0x80 ||
            potentialExtElement.tag == 0xA0 ||
            potentialExtElement.tag == 0x80 ||
            potentialExtElement.tag == 0;

            if (isTaggedZero) {
              // This is a context-specific tag [0], which wraps the Extensions sequence

              // For EXPLICIT tagging, the tag wraps the SEQUENCE
              // The asn1lib should decode it, so check if it's already a sequence
              if (potentialExtElement is ASN1Sequence) {
                extensionsSequence = potentialExtElement;
              } else {
                // Try to extract the inner sequence from the tagged wrapper
                // For EXPLICIT [0], structure is: [0] { length, SEQUENCE { ... } }
                // We need to parse the encoded bytes to get the inner SEQUENCE
                try {
                  final octets = potentialExtElement.encodedBytes;
                  if (octets.isNotEmpty) {
                    // Parse from the bytes, skipping the outer tag wrapper
                    int offset = 0;

                    // Check for tag 0xA0 (context-specific [0] constructed)
                    if (offset < octets.length && octets[offset] == 0xA0) {
                      offset++; // Skip tag byte

                      // Parse DER length encoding
                      if (offset < octets.length) {
                        int lenByte = octets[offset];
                        if (lenByte & 0x80 == 0) {
                          // Short form: single byte length
                          offset += 1;
                        } else {
                          // Long form: multi-byte length
                          int lenLen = lenByte & 0x7F;
                          if (lenLen > 0 &&
                            lenLen <= 4 &&
                            offset + 1 + lenLen < octets.length) {
                            offset += 1 + lenLen;
                          } else {
                            offset = octets.length; // Skip this attempt
                          }
                        }
                      }

                      // Now parse the inner SEQUENCE (content after tag and length)
                      if (offset < octets.length) {
                        final innerBytes = octets.sublist(offset);
                        try {
                          final parser = ASN1Parser(
                            Uint8List.fromList(innerBytes),
                          );
                          final parsed = parser.nextObject();
                          if (parsed is ASN1Sequence) {
                            extensionsSequence = parsed;
                          } else {
                          }
                        } catch (parseError) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
                      } else {
                      }
                    } else {
                      // Try parsing the entire octets as a sequence (maybe the tag was already stripped)
                      try {
                        final parser = ASN1Parser(Uint8List.fromList(octets));
                        final parsed = parser.nextObject();
                        if (parsed is ASN1Sequence) {
                          extensionsSequence = parsed;
                        }
                      } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
                    }
                  }
                } catch (e, stackTrace) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
              }
            } else if (potentialExtElement is ASN1Sequence &&
              extIdx == tbsCertList.elements.length - 1) {
              // Last element might be extensions without explicit tagging (some CRLs)
              extensionsSequence = potentialExtElement;
            }

            if (extensionsSequence != null) {
              final keysBefore = result.keys.toList();
              _parseCrlExtensions(
                extensionsSequence,
                result,
                logs: parsingLogs,
              );
              final keysAfter = result.keys.toList();
              // If we successfully extracted at least one extension, we're done
              if (keysAfter.length > keysBefore.length ||
                result.containsKey('crlNumber')) {
                break; // Found extensions, no need to check further
              } else {
              }
            }
          }

          // Fallback: if we haven't found extensions yet, try parsing the last sequence element
          // as extensions (some CRLs may have untagged extensions)
          if (!result.containsKey('crlNumber') &&
            tbsCertList.elements.isNotEmpty) {
            final lastElement =
            tbsCertList.elements[tbsCertList.elements.length - 1];
            if (lastElement is ASN1Sequence &&
              lastElement.elements.isNotEmpty) {
              // Check if it looks like an Extensions sequence (contains sequences with OIDs)
              bool looksLikeExtensions = false;
              for (final elem in lastElement.elements) {
                if (elem is ASN1Sequence && elem.elements.isNotEmpty) {
                  if (elem.elements[0] is ASN1ObjectIdentifier) {
                    looksLikeExtensions = true;
                    break;
                  }
                }
              }
              if (looksLikeExtensions) {
                _parseCrlExtensions(lastElement, result, logs: parsingLogs);
              }
            }
          }
        }
      }
    }
  } catch (e) {
    // If ASN1 parsing fails, return empty result
    // Certificate Authority will be null, will fall back to filename extraction if needed
  }

  return result;
}

/// Parses a Distinguished Name (DN) from ASN1Sequence
/// DN structure: Name = SEQUENCE OF RelativeDistinguishedName
/// RelativeDistinguishedName = SET OF AttributeTypeAndValue
/// AttributeTypeAndValue = SEQUENCE { type OBJECT IDENTIFIER, value ANY }
String _parseDistinguishedName(ASN1Sequence dnSequence) {
  final parts = <String>[];

  try {
    // DN structure: Sequence contains Sets, each Set contains Sequences [OID, Value]
    // Process each element in the DN sequence
    for (int i = 0; i < dnSequence.elements.length; i++) {
      final element = dnSequence.elements[i];

      // Each element should be a Set (RelativeDistinguishedName)
      if (element is ASN1Set) {

        // Process each AttributeTypeAndValue in the Set
        for (final setElement in element.elements) {
          // AttributeTypeAndValue is a Sequence [OID, Value]
          if (setElement is ASN1Sequence && setElement.elements.length >= 2) {
            final oid = setElement.elements[0];
            final value = setElement.elements[1];

            // Skip NULL values
            if (value is ASN1Null) {
              continue;
            }

            // Extract OID string
            String oidString = '';
            if (oid is ASN1ObjectIdentifier) {
              // Try to get identifier property first
              try {
                final identifier = (oid as dynamic).identifier;
                if (identifier != null && identifier is String) {
                  oidString = identifier;
                } else {
                  // Parse from toString format: "ObjectIdentifier(2.5.4.6)"
                  final oidStr = oid.toString();
                  final match = RegExp(
                    r'ObjectIdentifier\(([^)]+)\)',
                  ).firstMatch(oidStr);
                  if (match != null && match.group(1) != null) {
                    oidString = match.group(1)!;
                  } else {
                    oidString = oidStr;
                  }
                }
              } catch (e) {
                final oidStr = oid.toString();
                final match = RegExp(
                  r'ObjectIdentifier\(([^)]+)\)',
                ).firstMatch(oidStr);
                if (match != null && match.group(1) != null) {
                  oidString = match.group(1)!;
                }
              }
            } else {
            }

            // Extract value string
            String valueString = '';
            if (value is ASN1PrintableString) {
              valueString = value.stringValue;
            } else if (value is ASN1UTF8String) {
              valueString = value.utf8StringValue;
            } else if (value is ASN1IA5String) {
              valueString = value.stringValue;
            } else if (value is ASN1BMPString) {
              valueString = value.stringValue;
            } else {
              // Try to get string representation as fallback
              try {
                final strValue = (value as dynamic).stringValue;
                if (strValue != null && strValue is String) {
                  valueString = strValue;
                }
              } catch (_) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
            }

            // Map OID to readable attribute name
            String attrName = _oidToName(oidString);

            if (attrName.isNotEmpty && valueString.isNotEmpty) {
              final attrPair = '$attrName=$valueString';
              parts.add(attrPair);
            } else {
            }
          } else {
          }
        }
      } else {
      }
    }
  } catch (e, stackTrace) {
    // If parsing fails, return a simple representation
  }

  final result = parts.isNotEmpty ? parts.join(', ') : '';
  return result;
}

/// Parses time from ASN1 UTCTime or GeneralizedTime
String? _parseTime(ASN1Object timeObj) {
  try {

    String timeString = '';

    // Try to extract DateTime directly from ASN1UtcTime
    if (timeObj is ASN1UtcTime) {
      try {
        // ASN1UtcTime should have a dateTimeValue property
        final dateTimeValue = (timeObj as dynamic).dateTimeValue;
        if (dateTimeValue != null && dateTimeValue is DateTime) {
          final result = dateTimeValue.toIso8601String();
          return result;
        }
      } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }

      // Try to parse from stringValue (UTCTime format: YYMMDDHHMMSSZ or YYMMDDHHMMZ)
      try {
        final stringValue = (timeObj as dynamic).stringValue;
        if (stringValue != null && stringValue is String) {
          // Will parse below in the common parsing section
          timeString = stringValue;
        }
      } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }

      // Try to extract from toString format: "UtcTime(2025-11-04 14:29:02.000Z)"
      try {
        final timeStr = timeObj.toString();
        final match = RegExp(r'UtcTime\(([^)]+)\)').firstMatch(timeStr);
        if (match != null && match.group(1) != null) {
          final dateTimeStr = match.group(1)!.trim();
          // Try to parse as ISO8601
          try {
            final dt = DateTime.parse(dateTimeStr);
            final result = dt.toIso8601String();
            return result;
          } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
        }
      } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
    }

    // For other time types, try similar approaches
    try {
      // Try to get timeValue property
      final timeValue = (timeObj as dynamic).timeValue;
      if (timeValue != null && timeValue is String) {
        timeString = timeValue;
      } else {
        // Try to get stringValue property
        final stringValue = (timeObj as dynamic).stringValue;
        if (stringValue != null && stringValue is String) {
          timeString = stringValue;
        } else {
          // Fallback to toString
          timeString = timeObj.toString();
        }
      }
    } catch (e) {
      // Fallback to toString
      timeString = timeObj.toString();
    }

    if (timeString.isEmpty) {
      return null;
    }

    // Clean up the time string - remove any non-time parts
    String cleanedTime = timeString
    .replaceAll(RegExp(r'[^\dZ+-\s:]'), '')
    .trim();

    // Try parsing UTCTime format (YYMMDDHHMMSSZ or YYMMDDHHMMZ)
    if (cleanedTime.length == 13 && cleanedTime.endsWith('Z')) {
      // YYMMDDHHMMSSZ format
      final match = RegExp(
        r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$',
      ).firstMatch(cleanedTime);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);
        final second = int.parse(match.group(6)!);

        final fullYear = year < 50 ? 2000 + year : 1900 + year;
        final dateTime = DateTime.utc(
          fullYear,
          month,
          day,
          hour,
          minute,
          second,
        );
        return dateTime.toIso8601String();
      }
    } else if (cleanedTime.length == 11 && cleanedTime.endsWith('Z')) {
      // YYMMDDHHMMZ format
      final match = RegExp(
        r'^(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$',
      ).firstMatch(cleanedTime);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);

        final fullYear = year < 50 ? 2000 + year : 1900 + year;
        final dateTime = DateTime.utc(fullYear, month, day, hour, minute);
        return dateTime.toIso8601String();
      }
    } else if (cleanedTime.length >= 15) {
      // GeneralizedTime format (YYYYMMDDHHMMSSZ)
      final match = RegExp(
        r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z?$',
      ).firstMatch(cleanedTime);
      if (match != null) {
        final year = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        final day = int.parse(match.group(3)!);
        final hour = int.parse(match.group(4)!);
        final minute = int.parse(match.group(5)!);
        final second = int.parse(match.group(6)!);

        final dateTime = DateTime.utc(year, month, day, hour, minute, second);
        return dateTime.toIso8601String();
      }
    }
  } catch (e) {
    // If parsing fails, return null
  }
  return null;
}

/// Parses CRL extensions to extract CRL Number and other extensions
void _parseCrlExtensions(
  ASN1Sequence extensionsSeq,
  Map<String, dynamic> result, {
    List<String>? logs,
  }) {
  final parsingLogs = logs ?? <String>[];
  try {
    // Extensions ::= SEQUENCE OF Extension
    // Extension ::= SEQUENCE {
    //   extnID      OBJECT IDENTIFIER,
    //   critical   BOOLEAN DEFAULT FALSE,
    //   extnValue   OCTET STRING
    // }

    for (final extension in extensionsSeq.elements) {
      if (extension is! ASN1Sequence || extension.elements.isEmpty) {
        continue;
      }

      final extnID = extension.elements[0];
      if (extnID is! ASN1ObjectIdentifier) {
        continue;
      }

      // Extract OID string
      String oid = '';
      try {
        final identifier = (extnID as dynamic).identifier;
        if (identifier != null && identifier is String) {
          oid = identifier;
        } else {
          final oidStr = extnID.toString();
          final match = RegExp(
            r'ObjectIdentifier\(([^)]+)\)',
          ).firstMatch(oidStr);
          if (match != null && match.group(1) != null) {
            oid = match.group(1)!;
          }
        }
      } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }

      if (oid.isEmpty) {
        continue;
      }

      // Get extension value (OCTET STRING)
      dynamic extnValue;
      int valueIndex = 1;

      // Check if critical is present (2nd element might be boolean)
      if (extension.elements.length > 1 &&
        extension.elements[1] is ASN1Boolean) {
        valueIndex = 2; // Skip critical boolean
      }

      if (extension.elements.length > valueIndex) {
        extnValue = extension.elements[valueIndex];
      }

      // Process known extensions
      switch (oid) {
        case '2.5.29.20': // CRL Number (RFC 5280, Section 5.2.3)
        // CRL Number is a non-critical extension containing an INTEGER (0..MAX)
        if (extnValue is ASN1OctetString) {
          final bytes = extnValue.octets;
          if (bytes.isNotEmpty) {
            try {
              final parser = ASN1Parser(Uint8List.fromList(bytes));
              final integerObj = parser.nextObject();
              if (integerObj is ASN1Integer) {
                try {
                  // ASN1Integer doesn't have a value property, decode from encodedBytes
                  final encodedBytes = integerObj.encodedBytes;
                  if (encodedBytes.isNotEmpty) {
                    // Skip tag and length bytes to get to the integer value
                    int offset = 1; // Skip tag byte (0x02 for INTEGER)
                    if (encodedBytes.length > offset) {
                      int lenByte = encodedBytes[offset];
                      if (lenByte & 0x80 == 0) {
                        // Short form: single byte length
                        offset += 1;
                      } else {
                        // Long form: multi-byte length
                        int lenLen = lenByte & 0x7F;
                        if (lenLen > 0 &&
                          lenLen <= 4 &&
                          offset + 1 + lenLen < encodedBytes.length) {
                          offset += 1 + lenLen;
                        }
                      }
                    }

                    if (offset < encodedBytes.length) {
                      final valueBytes = encodedBytes.sublist(offset);
                      // Decode BigInt from bytes (two's complement for signed integers)
                      BigInt crlNumber = BigInt.zero;
                      for (int i = 0; i < valueBytes.length; i++) {
                        crlNumber =
                        (crlNumber << 8) | BigInt.from(valueBytes[i]);
                      }

                      // Handle two's complement for negative numbers (if MSB is set)
                      // CRL numbers should always be positive, but handle it just in case
                      if (valueBytes.isNotEmpty &&
                        (valueBytes[0] & 0x80) != 0) {
                        // Negative number in two's complement - shouldn't happen for CRL numbers
                        final mask =
                        (BigInt.one << (valueBytes.length * 8)) -
                        BigInt.one;
                        crlNumber = crlNumber - (mask + BigInt.one);
                      }

                      // Format as lowercase hex without 0x prefix, padded to even bytes
                      final hexStr = crlNumber
                      .toRadixString(16)
                      .toLowerCase();
                      // Pad to even number of hex digits (multiple of 2 for full bytes)
                      final paddedHex = hexStr.length.isOdd
                      ? '0$hexStr'
                      : hexStr;
                      result['crlNumber'] = paddedHex;
                      parsingLogs.add(
                        'Extracted CRL Number: ${result['crlNumber']}',
                      );
                    } else {
                    }
                  } else {
                  }
                } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
              } else {
              }
            } catch (e) {
      // Intentionally ignored: fall through to the next parsing strategy.
    }
          }
        } else {
        }
        break;
        default:
      }
    }
  } catch (e) {
    // If extension parsing fails, continue
  }
}

/// Maps OID to readable attribute name
String _oidToName(String oid) {
  // Common X.500 attribute OIDs
  switch (oid) {
    case '2.5.4.3': // CN - Common Name
    return 'CN';
    case '2.5.4.6': // C - Country
    return 'C';
    case '2.5.4.7': // L - Locality
    return 'L';
    case '2.5.4.8': // ST - State/Province
    return 'ST';
    case '2.5.4.10': // O - Organization
    return 'O';
    case '2.5.4.11': // OU - Organizational Unit
    return 'OU';
    case '2.5.4.5': // serialNumber
    return 'serialNumber';
    default:
    return '';
  }
}
