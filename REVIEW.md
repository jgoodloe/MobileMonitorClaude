# Code Review: MobileMonitor → Claude Edition

This document captures the review of the original [jgoodloe/MobileMonitor](https://github.com/jgoodloe/MobileMonitor), the performance and quality issues found, how each was addressed in this fork, and a roadmap of suggested features.

The original is a working, useful app — the issues below are about scaling it, keeping the UI smooth, and making it easier to maintain, not about correctness of the core monitoring logic (which is sound and was preserved).

---

## Performance findings & fixes

### 1. Sequential monitoring of all targets (highest impact)
**Original:** `monitor_screen.dart` checked every URL, then every DNS host, then every CRL, strictly one after another in a single `for`-loop pass, with deliberate `Future.delayed` pauses inserted between items and between groups. With the default set (2 URLs + 5 DNS + 3 CRLs) plus 10–15s timeouts, a refresh where several targets are unreachable could take well over a minute.

**Fix:** `MonitorController.refresh()` runs the three groups concurrently with `Future.wait`, and items within a group run in parallel too. Total refresh time now approximates the slowest single group instead of the sum of everything. Each result updates its row independently.

### 2. ~120 `print()` calls in the CRL parse path
**Original:** `crl_verifier.dart` contained ~151 `print()` statements, most inside the per-CRL ASN.1 parser, several interpolating large objects (`toString()` of ASN.1 structures, full result maps). These executed on **every** parse, in release builds too. `print()` is synchronous I/O and the string interpolation is pure waste when nobody's watching a console.

**Fix:** The parser was moved to `crl_parser.dart` with all `print()` removed. Diagnostics now use the `parsingLogs` list that already existed (and is shown in the detail view), plus a `logging`-based logger that is silent in release builds.

### 3. Two network round-trips per HTTPS URL
**Original:** `url_monitor.dart` made the `dio.get()` request, then opened a **separate** `HttpClient` connection to the same host purely to read the certificate — doubling connections for every HTTPS target, on every refresh.

**Fix:** The check still measures status/latency via one request and only fetches the certificate once when needed. The full response body is also drained as a stream rather than buffered, so large pages don't sit in memory just to be discarded.

### 4. Heavy parsing coupled to UI state
**Original:** All orchestration lived in the `State` object and mutated big lists via `setState`, rebuilding the whole tab subtree on each of many updates. Artificial `await Future.delayed(Duration.zero)` "yields" were sprinkled in to keep the UI from janking.

**Fix:** State moved to a `ChangeNotifier`; the screen uses `AnimatedBuilder` and per-item `ValueKey`s so the list diffs efficiently. Because the expensive ASN.1 work runs in an isolate via `compute()`, the UI thread stays free and the manual yield hacks are gone.

### 5. Incorrect ping timing on fallback port
**Original (bug):** `PingService.pingWithTime` started a stopwatch, and if port 80 failed it called `stopwatch.reset()` before trying port 443 — but never `start()`ed it again, so an HTTPS-only host reported a near-zero ping time.

**Fix:** Each port attempt gets its own fresh, running stopwatch.

### 6. `CrlValidityInfo.fromJson` dropped fields (bug)
**Original (bug):** The deserializer didn't read `timeUntilInvalid` or `parsingLogs`, so any persisted/round-tripped CRL lost its countdown and logs.

**Fix:** Both fields are now restored; covered by a regression test in `test/models_test.dart`.

### 7. Repeated `SharedPreferences` round-trips
**Original:** The refresh path awaited URLs, DNS hosts, and CRL URLs as separate calls.

**Fix:** `ConfigurationManager.load()` returns one immutable `MonitorConfig` snapshot in a single await.

### 8. Scattered magic numbers
**Original:** Timeouts, the 30-day cert window, 1-hour CRL window, retry counts, and the 10 MB cap were duplicated across files.

**Fix:** Centralized in `utils/app_config.dart` so behavior is auditable and testable.

---

## Maintainability / structure

- The CRL parser (~900 lines) was separated from networking and UI, with no Flutter dependencies, so it's unit-testable and isolate-safe.
- Models are now `@immutable` with value equality, enabling cheaper widget diffing.
- A reusable `MonitorItemCard` replaces the large inline card builder.
- `flutter_lints` is enabled with stricter rules (incl. `avoid_print`, `strict-casts`).
- Real unit tests were added (the original `test/` was effectively empty).

---

## Suggested features (roadmap)

Ordered roughly by value-to-effort. None of these are implemented yet — they're the natural next steps.

**Near term**
1. **Background/periodic checks + local notifications.** Use `workmanager` (Android) / BGTaskScheduler (iOS) to run checks on an interval and notify on a status change or an imminent cert/CRL expiry. This is the single biggest jump in usefulness for an ops tool.
2. **Status history & uptime %.** Persist each check result (SQLite via `drift`/`sqflite`) and show a sparkline + 24h/7d uptime per target.
3. **OCSP checking.** The default targets already include an `ocsp.` host — add real OCSP request/response validation alongside CRLs.
4. **Per-target configuration.** Custom timeout, check interval, and an enable/disable toggle per item.
5. **Export / import config.** Share the target list as JSON so a team can standardize what they monitor.

**Medium term**
6. **Full certificate chain inspection.** Show the whole chain, key sizes, signature algorithms, and SANs — relevant for PIV/PIV-I and FIPS 201 contexts.
7. **CRL delta + signature verification.** Verify the CRL signature against the issuing CA and support delta CRLs, not just availability + parsing.
8. **Search / filter / grouping** across all targets, and a single "all" overview tab with counts (up/down/warning).
9. **Configurable expiry thresholds** surfaced in Settings (the 30-day / 1-hour windows are currently constants).
10. **Latency thresholds & "degraded" state.** Treat slow-but-up as a distinct amber state.

**Longer term**
11. **Optional backend sync / webhooks** (Slack/Teams/email) so alerts reach a channel, not just the device.
12. **Post-quantum / algorithm visibility.** Flag certificates and CRLs by signature algorithm and highlight deprecated ones — useful given PQC migration planning.
13. **Widgets / home-screen glanceable status** and a watchOS/Wear companion.
14. **Accessibility & localization** pass.

---

## Notes

- All original default targets and the "accept all certificates / allow cleartext" monitoring posture were intentionally preserved.
- The ASN.1 parsing logic was ported faithfully; only the debug output was removed. If you later want stricter parsing, that's a good place to add the signature-verification feature (#7).
