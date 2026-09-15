#!/usr/bin/env bash
set -euo pipefail

# EN: Keep every target and the product blueprint on one explicit build number.
# ES: Mantiene todos los targets y el plano del producto en un único número de compilación explícito.
# 中文：确保所有 Target 与产品总纲使用同一个明确的 Build 号。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_FILE="${PROJECT_DIR}/CrazyDashboard.xcodeproj/project.pbxproj"
BLUEPRINT_FILE="${PROJECT_DIR}/APP_FEATURE_BLUEPRINT.md"
EXPECTED_BUILD="${1:-62}"
EXPECTED_MARKETING_VERSION="${2:-2.0.8}"

fail() {
    printf 'version validation failed: %s\n' "$1" >&2
    exit 1
}

[[ -f "$PROJECT_FILE" ]] || fail "project.pbxproj not found"
[[ -f "$BLUEPRINT_FILE" ]] || fail "APP_FEATURE_BLUEPRINT.md not found"

build_versions="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$PROJECT_FILE" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ "$build_versions" == "$EXPECTED_BUILD" ]] || fail "project build versions are '${build_versions}', expected '${EXPECTED_BUILD}'"

marketing_versions="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$PROJECT_FILE" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
[[ "$marketing_versions" == "$EXPECTED_MARKETING_VERSION" ]] || fail "marketing versions are '${marketing_versions}', expected '${EXPECTED_MARKETING_VERSION}'"

grep -Eq "Build[[:space:]]+${EXPECTED_BUILD}([^0-9]|$)" "$BLUEPRINT_FILE" || fail "blueprint does not declare Build ${EXPECTED_BUILD}"
grep -Eq "CURRENT_PROJECT_VERSION[^0-9]+${EXPECTED_BUILD}([^0-9]|$)" "$BLUEPRINT_FILE" || fail "blueprint does not declare CURRENT_PROJECT_VERSION = ${EXPECTED_BUILD}"

printf 'version validation passed: marketing=%s build=%s\n' "$EXPECTED_MARKETING_VERSION" "$EXPECTED_BUILD"

