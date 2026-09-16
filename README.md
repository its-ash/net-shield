<div align="center">

# NetShield

### Local DNS Firewall for Android

On-device DNS filtering powered by Android's `VpnService` — block ads, trackers, malware, and telemetry at the network layer without root.

</div>

---

## Overview

NetShield intercepts DNS queries from all apps on the device via a local VPN tunnel, then filters them against configurable blocklists and custom rules. No traffic leaves the device unfiltered, and no external proxy is used — resolution happens against your chosen upstream DNS resolver (system, UDP, TCP, DoT, or DoH).

Built with Flutter + a native Kotlin DNS engine.

## Features

| Area | What it does |
| --- | --- |
| **DNS Firewall** | Intercepts every DNS query via `VpnService` and applies allow/block rules before resolution. |
| **Blocklists** | Ships a default blocklist of well-known ad, tracker, malware, and telemetry domains. Add remote lists or import local files. |
| **Custom Rules** | Add per-domain rules with exact or suffix matching, categorised as ads / trackers / malware / telemetry / custom. |
| **Allowlist** | Override blocklist matches for specific domains you want to leave untouched. |
| **Per-App Rules** | Let selected apps bypass protection entirely, or protect everything except a chosen few. |
| **DNS Servers** | Configure upstream resolvers — system default, plain UDP/TCP, DNS-over-TLS (DoT), or DNS-over-HTTPS (DoH). |
| **Activity Log** | Live stream of every query with domain, source app, action (blocked/allowed), matched rule, and category. |
| **Statistics** | Aggregate counts, block percentage, cache hits/misses, active rule count, and resolver in use. |
| **Test Mode** | Sandbox to validate rules and resolver behaviour without affecting real traffic. |
| **Dev Diagnostics** | Low-level engine stats, last error, and native bridge health for debugging. |
| **Import / Export** | Back up and restore rules and settings via file. |
| **Dark Mode** | System-aware light/dark theme via the shared `theme` package. |

## Screens

```
Dashboard → start/stop VPN, live stats, quick toggles
Rules     → manage blocklist + custom + allowlist rules
Settings  → theme, DNS servers, import/export, about
```

Additional routes: `/blocklists`, `/allowlist`, `/custom-rules`, `/apps`, `/dns-servers`, `/statistics`, `/test`, `/dev`, `/about`.

## Tech Stack

- **Flutter** `^3.12.2` — UI + Dart logic
- **Kotlin** — native `VpnService` + minimal DNS engine (platform channels)
- **Riverpod** `2.6` — state management (`flutter_riverpod` + code-gen)
- **go_router** `14.6` — declarative routing
- **shared_preferences** — local persistence
- **file_picker** — import/export
- **theme** — shared design system ([github.com/its-ash/theme](https://github.com/its-ash/theme))

## Architecture

```
lib/
├── main.dart                  # Entry, ProviderScope, MaterialApp.router
├── data/
│   └── default_blocklist.dart # Shipped ad/tracker/malware/telemetry domains
├── models/
│   └── models.dart            # RuleEntry, BlocklistSource, DnsResolverConfig,
│                              # AppRule, QueryLogEntry, VpnStats, enums
├── providers/
│   └── providers.dart         # Riverpod providers (VPN state, settings, rules)
├── router/
│   └── app_router.dart        # GoRouter config + AppShell (bottom nav)
├── screens/                   # 14 screens (dashboard, rules, settings, …)
├── services/
│   ├── storage_service.dart   # SharedPreferences wrapper
│   └── vpn_bridge.dart        # Method/Event channel bridge to Kotlin engine
└── ...

android/app/src/main/          # Kotlin VpnService + DNS resolver implementation
```

**Native bridge** — `VpnBridge` talks to Kotlin via:
- MethodChannel `com.itsash.local_dns_firewall/vpn` — `prepareVpn`, `startVpn`, `stopVpn`, `getStats`, rule sync.
- EventChannel `com.itsash.local_dns_firewall/logs` — streaming `QueryLogEntry` events.

## Getting Started

### Prerequisites

- Flutter `>= 3.12` (Dart `^3.12.2`)
- Android SDK (min target per `android/app/build.gradle.kts`)
- A physical device or emulator with API level supporting `VpnService`

### Build & Run

```bash
# Install dependencies
flutter pub get

# Run on a connected device
make run          # → flutter run

# Build a release APK
make build        # → flutter build apk --release

# Deploy (commit + push to main)
make deploy
```

### Import the project

```bash
git clone https://github.com/its-ash/automate.git
cd automate
flutter pub get
flutter run
```

## Rule Model

Each rule is a `RuleEntry`:

| Field | Type | Notes |
| --- | --- | --- |
| `domain` | `String` | The domain to match. |
| `category` | `RuleCategory` | `ads` · `trackers` · `malware` · `telemetry` · `custom` |
| `exact` | `bool` | `true` = exact match, `false` = suffix match (subdomains included). |
| `enabled` | `bool` | Toggle without deleting. |

Upstream resolvers are `DnsResolverConfig` with protocol `system` · `udp` · `tcp` · `dot` · `doh`.

## Live Site

A static landing/docs page is published via GitHub Pages at **[netshield.itsash.in](https://netshield.itsash.in)** (see `CNAME`).

## License

Private project — not currently published to pub.dev. See `pubspec.yaml` (`publish_to: 'none'`).

---

<div align="center">

Built with Flutter · Powered by Android `VpnService`

</div>
