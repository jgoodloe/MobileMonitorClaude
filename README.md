# MobileMonitor (Claude Edition)

A Flutter network-monitoring app that checks the availability and status of **URLs**, **DNS hosts**, and **Certificate Revocation Lists (CRLs)**, with SSL/CRL expiry tracking. This is a re-engineered fork of [jgoodloe/MobileMonitor](https://github.com/jgoodloe/MobileMonitor) focused on performance, architecture, and maintainability while preserving all original behavior and defaults.

See [`REVIEW.md`](REVIEW.md) for the full code review, the specific performance issues found in the original, and what changed here.

## What's new vs. the original

- **Concurrent monitoring.** URL, DNS, and CRL groups run in parallel instead of one long sequential pass, so a refresh takes about as long as the slowest group rather than the sum of all three.
- **State extracted from the UI.** A `MonitorController` (`ChangeNotifier`) owns all orchestration and state; the screen just renders it. The original drove everything through `setState` inside the widget.
- **No `print()` in the hot path.** The CRL parser shed ~120 debug `print()` calls that previously ran on every parse (including release builds). Diagnostics now flow through structured logging and the existing per-CRL parsing-log list.
- **One connection per HTTPS check.** Certificate info is captured without opening a second full request per URL.
- **Parser isolated.** The 900-line ASN.1 CRL parser lives in its own file and runs in a background isolate via `compute()`, cleanly separated from networking and UI.
- **Bug fixes.** Corrected `CrlValidityInfo` deserialization (it previously dropped `timeUntilInvalid` and `parsingLogs`) and fixed ping timing on the HTTPS fallback port.
- **Dark mode**, centralized theming, shared formatters, and real unit tests.

## Features

- URL HTTP/HTTPS availability checks with response-time measurement
- DNS resolution with on-demand TCP "ping" of resolved IPs
- CRL download + ASN.1 parsing: issuer/CA, CRL number, revoked count, this/next update
- Certificate expiry warnings (within 30 days) and CRL expiry warnings (within 1 hour)
- Live, per-item status updates across three tabs
- Configurable targets with persistence; reset to defaults

## Requirements

- Flutter SDK 3.24+ (Dart 3.5+)
- Android: min SDK 21, target SDK 34
- iOS: 12.0+

## Getting started

```bash
flutter pub get
flutter run
```

Run the tests:

```bash
flutter test
```

Build:

```bash
flutter build apk --release      # Android
flutter build ios --release      # iOS (requires Xcode + signing)
```

## Project structure

```
lib/
├── main.dart                       # Entry point, nav shell, theming
├── models/
│   └── monitor_status.dart         # Data models (+ equality, fixed JSON)
├── services/
│   ├── monitor_controller.dart     # Orchestration & state (ChangeNotifier)
│   ├── url_monitor.dart            # HTTP/HTTPS + certificate checks
│   ├── dns_resolver.dart           # DNS resolution
│   ├── ping_service.dart           # TCP reachability
│   ├── crl_verifier.dart           # CRL fetch + validity assembly
│   ├── crl_parser.dart             # ASN.1 parsing (isolate, no UI deps)
│   └── configuration_manager.dart  # Persisted settings (batched load)
├── screens/
│   ├── monitor_screen.dart
│   ├── detail_screen.dart
│   └── settings_screen.dart
├── widgets/
│   └── monitor_item_card.dart      # Reusable status card
├── theme/app_theme.dart
└── utils/                          # config, logging, formatters
```

## Default monitoring targets

The default URLs, DNS hosts, and CRL URLs match the original (XTec AuthentX / xpki endpoints) and can be changed in **Settings**.

## Security notes

For monitoring purposes the app accepts all TLS certificates (including self-signed) and permits cleartext HTTP (needed for HTTP CRL distribution points). All checks are read-only.

## License

MIT — see [LICENSE](LICENSE).
