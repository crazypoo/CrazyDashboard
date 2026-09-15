#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 67 static, pure-model, documentation, and protected-boundary gates without touching a vehicle.
# ES: Ejecuta las puertas estáticas, de modelos puros, documentación y límites protegidos de Build 67 sin tocar un vehículo.
# 中文：执行 Build 67 静态、纯模型、文档和冻结边界门禁，不操作任何车辆。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
BUILD_DOC="${PROJECT_DIR}/docs/history/builds/BUILD_067_DASHBOARD_PROTOCOL_CORRECTION.md"

fail() {
    printf 'Build 67 checks failed: %s\n' "$1" >&2
    exit 1
}

"${SCRIPT_DIR}/validate_project_versions.sh" 67 2.0.8
[[ -f "${BUILD_DOC}" ]] || fail "Build 67 implementation record is missing"
plutil -lint "${PROJECT_FILE}"
git -C "${PROJECT_DIR}" diff --check

if git -C "${PROJECT_DIR}" diff --quiet -- \
    Global/BLE/PTBluetoothManager.swift \
    Global/OBD/Function/PTHiddenOBDConnector.swift \
    Global/OBD/Function/PTOBDCommand.swift \
    && git -C "${PROJECT_DIR}" diff --cached --quiet -- \
    Global/BLE/PTBluetoothManager.swift \
    Global/OBD/Function/PTHiddenOBDConnector.swift \
    Global/OBD/Function/PTOBDCommand.swift; then
    printf 'protected transport files unchanged\n'
else
    fail "protected transport files changed"
fi

rg -q 'CURRENT_PROJECT_VERSION = 67;' "${PROJECT_FILE}" || fail "project targets are not on Build 67"
rg -q 'MARKETING_VERSION = 2.0.8;' "${PROJECT_FILE}" || fail "marketing version is not 2.0.8"
rg -q 'PTDashboardClock' "${PROJECT_DIR}/Global/BLE/PTBluetoothManagerModels.swift" || fail "RTC model is missing"
rg -q 'rollingCounterRaw' "${PROJECT_DIR}/Global/BLE/PTBluetoothManagerModels.swift" || fail "rolling counter model is missing"
rg -q 'PTDashboardProtocolMarker' "${PROJECT_DIR}/Global/OBD/ViewController/PTCANLabViewController.swift" || fail "CAN marker UI is missing"

# EN: Parse Build 67 code with Swift 6 before invoking the dependency-heavy workspace build.
# ES: Analiza el código de Build 67 con Swift 6 antes de iniciar la compilación del workspace con dependencias.
# 中文：在调用依赖较多的工作区构建前，先用 Swift 6 解析 Build 67 代码。
xcrun swiftc -parse -swift-version 6 \
    "${PROJECT_DIR}/Global/BLE/PTBluetoothManagerModels.swift" \
    "${PROJECT_DIR}/Global/BLE/PTXP400BLEProtocolContract.swift" \
    "${PROJECT_DIR}/Global/BLE/PTXP400TelemetryDecoder.swift" \
    "${PROJECT_DIR}/Global/BLE/PTBluetoothServerManager+Diagnostics.swift" \
    "${PROJECT_DIR}/Global/BLE/PTBluetoothServerManager+Mock.swift" \
    "${PROJECT_DIR}/Global/Dashboard/Views/PTIndicatorPanel.swift" \
    "${PROJECT_DIR}/Global/Dev/PTECUSnifferOverlay.swift" \
    "${PROJECT_DIR}/Global/Global/PTVehicleConnectivityCoordinator.swift" \
    "${PROJECT_DIR}/Global/OBD/ViewController/PTCANLabViewController.swift" \
    "${PROJECT_DIR}/PTSpeedTests/PTCoreTests.swift"

# EN: Validate the string catalog as JSON without rewriting or normalizing localization data.
# ES: Valida el catálogo de cadenas como JSON sin reescribir ni normalizar los datos de localización.
# 中文：只校验字符串目录 JSON，不重写或规范化本地化数据。
python3 - "${PROJECT_DIR}/Global/Localizable.xcstrings" <<'PY'
from __future__ import annotations

# EN: Keep this gate dependency-free and read-only.
# ES: Mantén esta puerta sin dependencias y de solo lectura.
# 中文：保持该门禁无第三方依赖且只读。
import json
import sys
from pathlib import Path

json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print("localization catalog is valid JSON")
PY

"${SCRIPT_DIR}/docs_lint.sh"
python3 "${SCRIPT_DIR}/generate_docs_index.py" --check

if [[ "${RUN_XCODE_BUILD:-0}" == "1" ]]; then
    BUILD_LOG_PATH="${BUILD67_LOG_PATH:-${PROJECT_DIR}/.build/build67-xcodebuild.log}"
    DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build67}"
    mkdir -p "$(dirname "${BUILD_LOG_PATH}")"
    if ! xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "generic/platform=iOS" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build-for-testing >"${BUILD_LOG_PATH}" 2>&1; then
        tail -120 "${BUILD_LOG_PATH}" >&2
        exit 1
    fi
    rg -q '\*\* TEST BUILD SUCCEEDED \*\*' "${BUILD_LOG_PATH}"
    target_build_message="; Debug build-for-testing passed"
else
    target_build_message="; target build is opt-in"
fi

# EN: Full Xcode and vehicle checks remain explicit opt-in gates because the workspace may lack local Pods products.
# ES: Las comprobaciones completas de Xcode y del vehículo siguen siendo puertas explícitas porque pueden faltar productos Pods locales.
# 中文：完整 Xcode 和车辆检查保持显式可选，因为工作区可能缺少本地 Pods 产物。
printf 'Build 67 static checks passed%s; real-device and vehicle validation remains separate.\n' "${target_build_message}"
