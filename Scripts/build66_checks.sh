#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 66 static, pure-model, protected-boundary, and optional workspace gates without touching a vehicle.
# ES: Ejecuta las puertas estáticas, de modelos puros y de límites protegidos de Build 66 sin tocar un vehículo.
# 中文：执行 Build 66 静态、纯模型和冻结边界门禁，不操作任何车辆。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
BUILD_DOC="${PROJECT_DIR}/BUILD66_GPS_SPEED_FALLBACK.md"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build66}"
BUILD_LOG_PATH="${BUILD66_LOG_PATH:-${PROJECT_DIR}/.build/build66-xcodebuild.log}"

fail() {
    printf 'Build 66 checks failed: %s\n' "$1" >&2
    exit 1
}

"${SCRIPT_DIR}/validate_project_versions.sh" 66 2.0.8
[[ -f "${BUILD_DOC}" ]] || fail "Build 66 implementation record is missing"
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

rg -q 'CURRENT_PROJECT_VERSION = 66;' "${PROJECT_FILE}"
rg -q 'MARKETING_VERSION = 2.0.8;' "${PROJECT_FILE}"
rg -q 'PTVehicleSpeedResolver.swift in Sources' "${PROJECT_FILE}"
rg -q 'PTGPSSpeedProvider.swift in Sources' "${PROJECT_FILE}"
rg -q 'PTBuild66FeatureFlags.swift in Sources' "${PROJECT_FILE}"
rg -q 'PTVehicleTelemetryConsumer' "${PROJECT_DIR}/Global/PTMotoInfoViewController.swift" \
    || fail "PTMotoInfoViewController is not connected to the unified telemetry consumer"

# EN: The speed layer must not create a competing continuous location owner.
# ES: La capa de velocidad no debe crear otro propietario continuo de ubicación.
# 中文：速度层不得创建竞争性的持续定位所有者。
if rg -n 'CLLocationManager|AMapLocationManager' \
    "${PROJECT_DIR}/Global/Global/PTVehicleSpeedResolver.swift" \
    "${PROJECT_DIR}/Global/Global/PTGPSSpeedProvider.swift" \
    "${PROJECT_DIR}/Global/Global/PTBuild66FeatureFlags.swift"; then
    fail "Build 66 speed files create a location manager"
fi

# EN: Parse the pure Build 66 types with Swift 6 before invoking the full workspace build.
# ES: Analiza los tipos puros de Build 66 con Swift 6 antes de compilar todo el workspace.
# 中文：在完整工程编译前，先用 Swift 6 解析 Build 66 纯类型。
xcrun swiftc -parse -swift-version 6 \
    "${PROJECT_DIR}/Global/Global/PTVehicleSpeedResolver.swift" \
    "${PROJECT_DIR}/Global/Global/PTGPSSpeedProvider.swift" \
    "${PROJECT_DIR}/PTSpeedTests/PTVehicleSpeedResolverTests.swift" \
    "${PROJECT_DIR}/PTSpeedTests/PTGPSSpeedProviderTests.swift" \
    "${PROJECT_DIR}/PTSpeedTests/PTBuild66SpeedIntegrationTests.swift"

mkdir -p "$(dirname "${BUILD_LOG_PATH}")"

if [[ "${RUN_XCODE_BUILD:-1}" == "1" ]]; then
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
fi

if [[ "${RUN_RELEASE_BUILD:-0}" == "1" ]]; then
    release_log="${BUILD_LOG_PATH%.log}-release.log"
    if ! xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -derivedDataPath "${DERIVED_DATA_PATH}-release" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build >"${release_log}" 2>&1; then
        tail -120 "${release_log}" >&2
        exit 1
    fi
    rg -q '\*\* BUILD SUCCEEDED \*\*' "${release_log}"
fi

if [[ "${RUN_SIMULATOR_TESTS:-0}" == "1" ]]; then
    # EN: XCTest execution is opt-in; it requires a compatible simulator and Pods architecture.
    # ES: La ejecución de XCTest es opcional; requiere un simulador y una arquitectura de Pods compatibles.
    # 中文：XCTest 实际执行按需开启，需要兼容的模拟器和 Pods 架构。
    xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        test \
        -only-testing:PTSpeedTests/PTVehicleSpeedResolverTests \
        -only-testing:PTSpeedTests/PTGPSSpeedProviderTests \
        -only-testing:PTSpeedTests/PTBuild66SpeedIntegrationTests
fi

printf 'Build 66 checks passed; real-device and vehicle validation remains manual.\n'
