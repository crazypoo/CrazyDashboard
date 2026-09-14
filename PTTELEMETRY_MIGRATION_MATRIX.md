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
| Peugeot Dashboard | `PTVehicleTelemetryBridge` / legacy manager | Unified projection | 🟨 compatibility path retained | static audit |
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

