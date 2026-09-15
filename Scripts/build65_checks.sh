#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 65 static, release, and protected-boundary checks without touching a vehicle.
# ES: Ejecuta las comprobaciones estáticas, de Release y de límites protegidos de Build 65 sin tocar un vehículo.
# 中文：执行 Build 65 静态、Release 和冻结边界检查，不操作任何车辆。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build65}"
BUILD_LOG_PATH="${BUILD65_LOG_PATH:-${PROJECT_DIR}/.build/build65-xcodebuild.log}"

"${SCRIPT_DIR}/validate_project_versions.sh" 65 2.0.8
plutil -lint "${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
git -C "${PROJECT_DIR}" diff --check

if git -C "${PROJECT_DIR}" diff --quiet -- \
    Global/OBD/Function/PTHiddenOBDConnector.swift \
    Global/OBD/Function/PTOBDCommand.swift \
    Global/BLE/PTBluetoothManager.swift \
    && git -C "${PROJECT_DIR}" diff --cached --quiet -- \
    Global/OBD/Function/PTHiddenOBDConnector.swift \
    Global/OBD/Function/PTOBDCommand.swift \
    Global/BLE/PTBluetoothManager.swift; then
    echo "protected transport files unchanged"
else
    echo "protected transport files changed" >&2
    exit 1
fi

rg -q 'CURRENT_PROJECT_VERSION = 65;' "${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
rg -q 'SWIFT_STRICT_CONCURRENCY = complete;' "${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
rg -q 'public static let publicReleaseDefault' "${PROJECT_DIR}/Global/Dev/PTBuild65Hardening.swift"
rg -q 'streamEvents\(' "${PROJECT_DIR}/Global/Global/PTCrazyTracePlatform.swift"
rg -q 'streamFrames\(' "${PROJECT_DIR}/Global/OBD/Function/PTCANRecorder.swift"
rg -q 'maximumPageSize' "${PROJECT_DIR}/Global/Dev/ProtocolResearch/PTProtocolEvidenceDatabase.swift"

# EN: Parse the pure Build 65 model with Swift 6 before invoking the full workspace build.
# ES: Analiza el modelo puro de Build 65 con Swift 6 antes de compilar todo el workspace.
# 中文：先用 Swift 6 解析纯 Build 65 模型，再执行完整工程编译。
xcrun swiftc -parse -swift-version 6 "${PROJECT_DIR}/Global/Dev/PTBuild65Hardening.swift"

mkdir -p "$(dirname "${BUILD_LOG_PATH}")"

if [[ "${RUN_XCODE_BUILD:-1}" == "1" ]]; then
    if ! xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "generic/platform=iOS" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        build-for-testing >"${BUILD_LOG_PATH}" 2>&1; then
        tail -120 "${BUILD_LOG_PATH}" >&2
        exit 1
    fi
    rg -q '\*\* TEST BUILD SUCCEEDED \*\*' "${BUILD_LOG_PATH}"
fi

if [[ "${RUN_RELEASE_BUILD:-1}" == "1" ]]; then
    release_log="${BUILD_LOG_PATH%.log}-release.log"
    if ! xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "${DERIVED_DATA_PATH}-release" \
        CODE_SIGNING_ALLOWED=NO \
        build >"${release_log}" 2>&1; then
        tail -120 "${release_log}" >&2
        exit 1
    fi
    rg -q '\*\* BUILD SUCCEEDED \*\*' "${release_log}"
fi

if [[ "${RUN_SIMULATOR_TESTS:-0}" == "1" ]]; then
    # EN: XCTest execution is opt-in because the available simulator and Pods architectures may differ.
    # ES: La ejecución de XCTest es opcional porque pueden diferir las arquitecturas del simulador y de Pods.
    # 中文：XCTest 实际运行按需开启，因为当前模拟器和 Pods 架构可能不一致。
    xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        test \
        -only-testing:PTSpeedTests/PTBuild65HardeningTests \
        -only-testing:PTSpeedTests/PTCrazyTraceBuild62Tests \
        -only-testing:PTSpeedTests/PTProtocolResearchLabBuild63Tests \
        -only-testing:PTSpeedTests/PTVehicleIdentityBuild64Tests
fi

echo "Build 65 checks passed"
