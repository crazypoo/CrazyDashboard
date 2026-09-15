#!/usr/bin/env bash
set -euo pipefail

# EN: Run the Build 62 version gate and compile the app/tests without signing a device.
# ES: Ejecuta la puerta de versión de Build 62 y compila la app/pruebas sin firmar un dispositivo.
# 中文：执行 Build 62 版本门禁，并在不签名真机的情况下编译 App 与测试。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${PROJECT_DIR}/.build/Build62}"

"${SCRIPT_DIR}/validate_project_versions.sh" 62 2.0.8

xcodebuild \
    -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
    -scheme PTSpeed \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    build-for-testing

if [[ "${RUN_SIMULATOR_TESTS:-0}" == "1" ]]; then
    # EN: CI runs only pure replay/database tests; hardware and transport tests stay out of automation.
    # ES: CI ejecuta solo pruebas puras de reproducción/base de datos; el hardware y el transporte quedan fuera.
    # 中文：CI 只运行纯回放和数据库测试，硬件及传输测试不进入自动化。
    xcodebuild \
        -workspace "${PROJECT_DIR}/CrazyDashboard.xcworkspace" \
        -scheme PTSpeed \
        -configuration Debug \
        -destination "${SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16,OS=latest}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGNING_ALLOWED=NO \
        test \
        -only-testing:PTSpeedTests/PTProtocolEvidenceDatabaseTests \
        -only-testing:PTSpeedTests/PTCrazyTraceBuild62Tests
fi
