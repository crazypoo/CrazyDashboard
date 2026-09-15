#!/usr/bin/env bash
set -euo pipefail

# EN: Run Build 63 gates and compile the passive research/replay test surface.
# ES: Ejecuta las puertas de Build 63 y compila la superficie de investigación/reproducción pasiva.
# 中文：执行 Build 63 门禁，并编译被动研究与回放测试范围。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build63}"

"${SCRIPT_DIR}/validate_project_versions.sh" 63 2.0.8

xcodebuild \
    -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
    -scheme PTSpeed \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing

if [[ "${RUN_SIMULATOR_TESTS:-0}" == "1" ]]; then
    # EN: Only deterministic data tests run in automation; vehicle and transport tests stay manual.
    # ES: La automatización ejecuta solo pruebas de datos deterministas; el vehículo y el transporte quedan manuales.
    # 中文：自动化只运行确定性数据测试，车辆与传输测试保留人工执行。
    xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        test \
        -only-testing:PTSpeedTests/PTProtocolResearchLabBuild63Tests \
        -only-testing:PTSpeedTests/PTProtocolEvidenceDatabaseTests \
        -only-testing:PTSpeedTests/PTCrazyTraceBuild62Tests
fi
