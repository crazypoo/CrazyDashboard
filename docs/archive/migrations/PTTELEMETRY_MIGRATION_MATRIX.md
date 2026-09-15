---
doc_id: CD-ARCHIVE-MIGRATION-TELEMETRY
title: PTVehicleTelemetry Build 61 Migration Matrix (Archived)
type: archive
status: archived
canonical: false
domain: telemetry-migration
owner: Jax
created: 2026-09-15
last_reviewed: 2026-09-15
archived_at: 2026-09-15
related_builds:
  - 61
supersedes: []
superseded_by:
  - ../../architecture/TELEMETRY_ARCHITECTURE.md
---

> Archived on 2026-09-15. This document is historical and must not be used as the current implementation plan. See the [telemetry architecture](../../architecture/TELEMETRY_ARCHITECTURE.md).

# PTVehicleTelemetry Build 61 Migration Matrix

> This is the Build 61 dependency audit. It records the current path, the target read-only path, and the validation boundary.
>
> Este documento registra la auditoría de dependencias de Build 61, la ruta actual, la ruta objetivo de solo lectura y el límite de validación.
>
> 这是 Build 61 的遥测依赖审计，记录当前路径、目标只读路径和验证边界。

## Canonical data path

```text
XP400 BLE / ELM327 OBD / GPS / Motion / Replay
                    ↓
PTVehicleConnectivityCoordinator
                    ↓
PTVehicleTelemetryBridge
                    ↓
PTUnifiedVehicleTelemetrySnapshot
                    ↓
PTVehicleTelemetryConsumerHub + domain projections
                    ↓
Dashboard / Ride / Instruments / Widget / Watch / CarPlay
```

`PTBluetoothManager`, `PTHiddenOBDConnector` and `PTOBDCommand` remain transport boundaries. This matrix never authorizes edits to those files.

## Consumer inventory

| Consumer | Current source | Build 61 target | Status | Validation |
| --- | --- | --- | --- | --- |
| Main Dashboard | Unified notification plus Motion/Location events | `PTVehicleTelemetryConsumerHub` + `PTDashboardProjection` | ✅ migrated | static + build; device pending |
| PTMotoInfo / Peugeot Dashboard | `PTVehicleTelemetryBridge` / legacy manager | Unified projection | ✅ speed migrated; other fields retain compatibility paths | static + build; device pending |
| Ride Experience | Coordinator snapshot, Widget status and BLE fields | `PTRideProjection` | 🟨 next migration | static audit |
| PTTripManager | BLE/OBD/Motion delegate sampling | producer-owned sampling | 🟨 intentionally unchanged | trip regression required |
| Instruments | Bridge, Coordinator and legacy manager | provider snapshots + `PTInstrumentProviderRegistry` | ✅ provider boundary added | static + build |
| Widget | App Group `PTWidgetSharedStatus` | `PTWidgetProjection` in the main-app writer | 🟨 storage compatibility retained | Widget build/device pending |
| Watch | Watch Connectivity application context | `PTWatchProjection` at the sender boundary | 🟨 storage compatibility retained | paired-device pending |
| CarPlay | View-controller-specific legacy reads | `PTCarPlayProjection` | 🟨 staged | CarPlay pending |
| Protocol Evidence | Bridge and Instrument singleton reads | injected snapshot/capture inputs | 🟨 boundary extracted | migration fixture pending |

## Compatibility rules

1. New read-only consumers must accept immutable `PTUnifiedVehicleTelemetrySnapshot` values.
2. A consumer must use per-signal freshness; `updatedAt` alone is not enough.
3. Existing App Group, Watch Connectivity and iCloud formats are unchanged in Build 61.
4. `PTMotoTelemetryManager` and `PTVehicleTelemetryBridge` remain compatibility facades until all callers migrate; no broad deprecation annotation is added in this build.
5. Replay telemetry and live telemetry use the same Unified snapshot contract. Ride-history replay remains a separate historical product feature until a later migration.

## Build 66 speed-resolution extension

Build 66 keeps the canonical path above and specializes only the `.speed` signal:

```text
XP400 BLE / ELM327 OBD ─┐
                        ├─ PTVehicleSpeedResolver ─┐
PTLocationEngine/AMap ──┘                          ├─ PTVehicleTelemetryBridge
CrazyTrace Replay ─────────────────────────────────┘
                                                      ↓
                                      PTUnifiedVehicleTelemetrySnapshot
```

The read-only speed policy is:

| Source | Maximum age | Priority | Notes |
| --- | ---: | ---: | --- |
| XP400 BLE | 1.5 s | 400 | Preferred live vehicle speed |
| ELM327 OBD | 2.0 s | 300 | Immediate fallback when XP400 is stale |
| GPS | 3.0 s | 200 | Reuses the existing location lease; 30 m horizontal accuracy and 3 m/s speed accuracy gates |
| Replay | Replay clock | explicit override | Only active while replay mode is active |

GPS samples are converted from m/s to km/h, pass a 3-sample median and EMA (`alpha = 0.45`), and clamp only values below 2 km/h to a valid `0 km/h`. A missing or rejected sample remains unavailable (`nil`), so unavailable is never confused with a stopped motorcycle.

`PTVehicleSpeedResolver` is owned by the `@MainActor` bridge. A higher-priority source needs two consecutive fresh samples to take over an already fresh source; a fresh lower-priority source takes over immediately when the current source expires or is removed. The main Dashboard and Peugeot Dashboard render speed only from the unified consumer boundary. `PTTripManager`, LiDAR safety logic, Widget/Watch and CarPlay retain their staged compatibility paths for later builds.

Build 66 validation is separated into Swift 6 unit tests, target compilation, offline trace compatibility, and real-device/vehicle checks. The latter still require iPhone GPS-only, GPS→OBD, OBD→XP400, disconnect fallback, background and low-power runs.
