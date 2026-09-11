// EN: Classify nearby adapters without requiring a YMOBD-only BLE service filter.
// ES: Clasifica adaptadores cercanos sin exigir un filtro BLE exclusivo de YMOBD.
// 中文：对附近适配器分类，不要求只能使用 YMOBD 专属 BLE 服务过滤。

import Foundation

public enum PTYMOBDDeviceCategory: String, Sendable {
    case obd
    case batteryTester
    case tpms
    case otaCapable
    case unknown
}

public struct PTYMOBDDeviceClassifier: Sendable {
    private static let knownOBDNames: Set<String> = [
        "OBDII", "MS310", "B25", "V500", "YM529", "YM329", "YM129", "YM819", "BT529",
        "OBD114", "OBD147", "BROM S10", "BROM S15", "BROM S20"
    ]

    private static let excludedNames: Set<String> = [
        "P300", "BT_00", "BT15", "BT17", "BT319", "BT369", "TPMS", "C15", "C35"
    ]

    private static let batteryTesterNames: Set<String> = ["BT_00", "BT15", "BT17", "BT319"]

    public init() {}

    public func category(
        forName name: String,
        advertisedServiceUUIDs: [String] = []
    ) -> PTYMOBDDeviceCategory {
        let normalizedName = Self.normalize(name)

        if normalizedName.contains("TPMS") {
            return .tpms
        }
        if Self.batteryTesterNames.contains(normalizedName) {
            return .batteryTester
        }
        if Self.excludedNames.contains(normalizedName) {
            return .otaCapable
        }
        if Self.knownOBDNames.contains(normalizedName)
            || advertisedServiceUUIDs.contains(where: Self.isFFF0) {
            return .obd
        }

        // EN: Keep generic matching narrow to avoid claiming unrelated BLE devices.
        // ES: Mantiene estrecha la coincidencia genérica para no reclamar dispositivos BLE ajenos.
        // 中文：收窄通用名称匹配，避免误认无关 BLE 设备。
        if normalizedName.contains("OBD")
            || normalizedName.contains("ELM")
            || normalizedName.hasPrefix("BROM")
            || normalizedName.hasPrefix("YM") {
            return .obd
        }
        return .unknown
    }

    public func isLikelyOBD(
        deviceName: String,
        advertisedServiceUUIDs: [String] = []
    ) -> Bool {
        category(forName: deviceName, advertisedServiceUUIDs: advertisedServiceUUIDs) == .obd
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func isFFF0(_ value: String) -> Bool {
        let compact = value.uppercased().replacingOccurrences(of: "-", with: "")
        return compact == "FFF0" || compact == "0000FFF000001000800000805F9B34FB"
    }
}
