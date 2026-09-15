#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 64 identity-model gates without exercising a vehicle transport.
# ES: Ejecuta las puertas de identidad de Build 64 sin activar ningún transporte del vehículo.
# 中文：执行 Build 64 身份模型门禁，不操作任何车辆传输。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build64}"

"${SCRIPT_DIR}/validate_project_versions.sh" 64 2.0.8

xcodebuild \
    -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
    -scheme PTSpeed \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing

if [[ "${RUN_SIMULATOR_TESTS:-0}" == "1" ]]; then
    # EN: These tests are deterministic data tests; ECU and transport validation remains manual.
    # ES: Estas pruebas son deterministas; la validación ECU y del transporte sigue siendo manual.
    # 中文：这些是确定性数据测试；ECU 与传输验证仍需人工实车执行。
    xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        test \
        -only-testing:PTSpeedTests/PTVehicleIdentityBuild64Tests \
        -only-testing:PTSpeedTests/PTArchitectureConsolidationTests
fi
