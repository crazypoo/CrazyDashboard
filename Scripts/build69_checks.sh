#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 69 static, pure-model, documentation, and frozen-boundary gates without touching a vehicle.
# ES: Ejecuta las puertas estáticas, de modelos puros, documentación y límites congelados de Build 69 sin tocar un vehículo.
# 中文：执行 Build 69 静态、纯模型、文档和冻结边界门禁，不操作任何车辆。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
BUILD_DOC="${PROJECT_DIR}/docs/history/builds/BUILD_069_PROTOCOL_SEMANTIC_EVIDENCE.md"

fail() {
    printf 'Build 69 checks failed: %s\n' "$1" >&2
    exit 1
}

"${SCRIPT_DIR}/validate_project_versions.sh" 69 2.0.8
[[ -f "${BUILD_DOC}" ]] || fail "Build 69 implementation record is missing"
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

rg -q 'CURRENT_PROJECT_VERSION = 69;' "${PROJECT_FILE}" || fail "project targets are not on Build 69"
rg -q 'MARKETING_VERSION = 2.0.8;' "${PROJECT_FILE}" || fail "marketing version is not 2.0.8"
for source in \
    'PTXP400SemanticEvidence.swift in Sources' \
    '../ELM327/PTBuild69OBDProtocolLayers.swift in Sources' \
    'PTBuild69ProtocolIntelligence.swift in Sources' \
    'PTBuild69Replay.swift in Sources' \
    'PTBuild69ProtocolSemanticTests.swift in Sources'; do
    rg -q "${source}" "${PROJECT_FILE}" || fail "${source} is not in Sources"
done
rg -q 'PTBuild69ProtocolEvidenceCoordinator.shared.ingestBLEFrame' \
    "${PROJECT_DIR}/Global/BLE/PTBluetoothServerManager+Diagnostics.swift" \
    || fail "Build 69 BLE evidence coordinator is not connected"
rg -q 'PTBuild69ELMNormalizer|PTBuild69ProtocolRouter' \
    "${PROJECT_DIR}/Global/OBD/ELM327/PTBuild69OBDProtocolLayers.swift" \
    || fail "Build 69 ELM/OBD/UDS layers are missing"
rg -q 'PTBuild69HistoricalReplayAnalyzer|PTBuild69ReplayAnalyzer' \
    "${PROJECT_DIR}/Global/Dev/PTBuild69Replay.swift" \
    || fail "Build 69 replay analyzers are missing"

# EN: Parse the pure Build 69 code with Swift 6 before invoking the dependency-heavy workspace build.
# ES: Analiza el código puro de Build 69 con Swift 6 antes de compilar el workspace con dependencias.
# 中文：在完整工程编译前，先用 Swift 6 解析 Build 69 纯代码。
xcrun swiftc -parse -swift-version 6 \
    "${PROJECT_DIR}/Global/BLE/PTXP400SemanticEvidence.swift" \
    "${PROJECT_DIR}/Global/OBD/ELM327/PTBuild69OBDProtocolLayers.swift" \
    "${PROJECT_DIR}/Global/Dev/PTBuild69ProtocolIntelligence.swift" \
    "${PROJECT_DIR}/Global/Dev/PTBuild69Replay.swift" \
    "${PROJECT_DIR}/PTSpeedTests/PTBuild69ProtocolSemanticTests.swift"

"${SCRIPT_DIR}/docs_lint.sh"
python3 "${SCRIPT_DIR}/generate_docs_index.py" --check

if [[ "${RUN_XCODE_BUILD:-0}" == "1" ]]; then
    BUILD_LOG_PATH="${BUILD69_LOG_PATH:-${PROJECT_DIR}/.build/build69-xcodebuild.log}"
    DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build69}"
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

# EN: Device, simulator, and vehicle evidence remain separate from static and compile gates.
# ES: La evidencia de dispositivo, simulador y vehículo permanece separada de las puertas estáticas y de compilación.
# 中文：设备、模拟器和车辆证据与静态检查、编译门禁分开记录。
printf 'Build 69 static checks passed%s; real-device and vehicle validation remains manual.\n' "${target_build_message}"
