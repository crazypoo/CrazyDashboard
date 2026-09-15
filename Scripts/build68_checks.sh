#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 68 static, pure-model, documentation, and protected-boundary gates without touching a vehicle.
# ES: Ejecuta las puertas estáticas, de modelos puros, documentación y límites protegidos de Build 68 sin tocar un vehículo.
# 中文：执行 Build 68 静态、纯模型、文档和冻结边界门禁，不操作任何车辆。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
BUILD_DOC="${PROJECT_DIR}/docs/history/builds/BUILD_068_OBD_DIAGNOSTIC_DEEP_MINING.md"

fail() {
    printf 'Build 68 checks failed: %s\n' "$1" >&2
    exit 1
}

"${SCRIPT_DIR}/validate_project_versions.sh" 68 2.0.8
[[ -f "${BUILD_DOC}" ]] || fail "Build 68 implementation record is missing"
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

rg -q 'CURRENT_PROJECT_VERSION = 68;' "${PROJECT_FILE}" || fail "project targets are not on Build 68"
rg -q 'MARKETING_VERSION = 2.0.8;' "${PROJECT_FILE}" || fail "marketing version is not 2.0.8"
rg -q 'PTBuild68OBDDeepDiagnostics.swift in Sources' "${PROJECT_FILE}" || fail "Build 68 production file is not in Sources"
rg -q 'PTBuild68OBDDeepDiagnosticsTests.swift in Sources' "${PROJECT_FILE}" || fail "Build 68 tests are not in Sources"
rg -q 'PTBuild68DiagnosticCoordinator.shared.start\(\)' "${PROJECT_DIR}/Global/Global/PTVehicleConnectivityCoordinator.swift" \
    || fail "Build 68 coordinator is not connected to vehicle lifecycle"
rg -q 'PTBuild68TraceRedactor' "${PROJECT_DIR}/Global/Log/PTProtocolDiscoveryRecorder.swift" \
    || fail "Build 68 redaction is not connected to protocol evidence"

# EN: Parse the pure Build 68 code with Swift 6 before invoking the dependency-heavy workspace build.
# ES: Analiza el código puro de Build 68 con Swift 6 antes de compilar el workspace con dependencias.
# 中文：在完整工程编译前，先用 Swift 6 解析 Build 68 纯代码。
xcrun swiftc -parse -swift-version 6 \
    "${PROJECT_DIR}/Global/OBD/Function/PTBuild68OBDDeepDiagnostics.swift" \
    "${PROJECT_DIR}/PTSpeedTests/PTBuild68OBDDeepDiagnosticsTests.swift"

"${SCRIPT_DIR}/docs_lint.sh"
python3 "${SCRIPT_DIR}/generate_docs_index.py" --check

if [[ "${RUN_XCODE_BUILD:-0}" == "1" ]]; then
    BUILD_LOG_PATH="${BUILD68_LOG_PATH:-${PROJECT_DIR}/.build/build68-xcodebuild.log}"
    DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build68}"
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
    rg -q '\*\* TEST BUILD SUCCEEDED \*\*' "${BUILD_LOG_PATH}" || fail "Xcode build did not report success"
    target_build_message='; Debug build-for-testing passed'
else
    target_build_message='; target build is opt-in'
fi

# EN: Device and vehicle evidence remain separate from static and compile gates.
# ES: La evidencia de dispositivo y vehículo permanece separada de las puertas estáticas y de compilación.
# 中文：设备和车辆证据与静态检查、编译门禁分开记录。
printf 'Build 68 static checks passed%s; real-device and vehicle validation remains manual.\n' "${target_build_message}"
