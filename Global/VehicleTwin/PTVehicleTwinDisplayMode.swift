//
//  PTVehicleTwinDisplayMode.swift
//  CrazyDashboard
//
//  EN: Display modes, camera presets and conservative performance policy for the Digital Twin.
//  ES: Modos de pantalla, presets de cámara y política conservadora de rendimiento del Digital Twin.
//  中文：数字孪生的显示模式、相机预设和保守性能策略。
//

import Foundation

enum PTVehicleTwinDisplayMode: String, CaseIterable, Equatable, Sendable {
    case automatic = "auto"
    case twoD = "2d"
    case threeD = "3d"

    var localizationKey: PTVehicleTwinCopyKey {
        switch self {
        case .automatic:
            return .modeAutomatic
        case .twoD:
            return .modeTwoD
        case .threeD:
            return .modeThreeD
        }
    }
}

enum PTVehicleTwin3DCameraPreset: String, CaseIterable, Equatable, Sendable {
    case front
    case rear
    case left
    case right
    case top
    case follow

    var localizationKey: PTVehicleTwinCopyKey {
        switch self {
        case .front:
            return .cameraFront
        case .rear:
            return .cameraRear
        case .left:
            return .cameraLeft
        case .right:
            return .cameraRight
        case .top:
            return .cameraTop
        case .follow:
            return .cameraFollow
        }
    }
}

enum PTVehicleTwin3DFallbackReason: String, Equatable, Sendable {
    case lowPowerMode
    case thermalPressure
    case rendererUnavailable

    var localizationKey: PTVehicleTwinCopyKey {
        switch self {
        case .lowPowerMode:
            return .fallbackLowPower
        case .thermalPressure:
            return .fallbackThermal
        case .rendererUnavailable:
            return .fallbackUnavailable
        }
    }
}

enum PTVehicleTwin3DPerformancePolicy {
    // EN: Thirty FPS caps work for a read-only vehicle visualization without competing with telemetry.
    // ES: Treinta FPS limita el trabajo de una visualización de solo lectura sin competir con la telemetría.
    // 中文：30 FPS 足以承载只读车辆可视化，同时避免与遥测争用资源。
    static let preferredFramesPerSecond = 30

    static func fallbackReason(
        lowPowerModeEnabled: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> PTVehicleTwin3DFallbackReason? {
        if lowPowerModeEnabled {
            return .lowPowerMode
        }
        switch thermalState {
        case .serious, .critical:
            return .thermalPressure
        default:
            return nil
        }
    }
}

@MainActor
final class PTVehicleTwinDisplayPreferences {
    static let shared = PTVehicleTwinDisplayPreferences()

    private let defaults: UserDefaults
    private let key = "pt_vehicle_twin_display_mode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: PTVehicleTwinDisplayMode {
        get {
            guard let rawValue = defaults.string(forKey: key),
                  let value = PTVehicleTwinDisplayMode(rawValue: rawValue) else {
                return .automatic
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: key)
        }
    }
}

enum PTVehicleTwinCopyKey: String, Sendable {
    case modeAutomatic = "vehicle_twin_mode_auto"
    case modeTwoD = "vehicle_twin_mode_2d"
    case modeThreeD = "vehicle_twin_mode_3d"
    case cameraFront = "vehicle_twin_camera_front"
    case cameraRear = "vehicle_twin_camera_rear"
    case cameraLeft = "vehicle_twin_camera_left"
    case cameraRight = "vehicle_twin_camera_right"
    case cameraTop = "vehicle_twin_camera_top"
    case cameraFollow = "vehicle_twin_camera_follow"
    case fallbackLowPower = "vehicle_twin_fallback_low_power"
    case fallbackThermal = "vehicle_twin_fallback_thermal"
    case fallbackUnavailable = "vehicle_twin_fallback_unavailable"
}

@MainActor
enum PTVehicleTwinCopy {
    static func text(_ key: PTVehicleTwinCopyKey) -> String {
        let resolved = PTDashboardConfig.languageFunc(text: key.rawValue)
        guard resolved == key.rawValue else { return resolved }

        // EN: Keep a local fallback until these keys are exported to every String Catalog locale.
        // ES: Mantén un fallback local hasta exportar estas claves a todos los locales del String Catalog.
        // 中文：在这些键导出到所有 String Catalog 语言前，保留本地回退文案。
        let language = PTDashboardConfig.selectedLanguageIdentifier
        switch (key, language) {
        case (.modeAutomatic, "zh-Hans"):
            return "自动"
        case (.modeAutomatic, "zh-Hant"):
            return "自動"
        case (.modeAutomatic, "ja"):
            return "自動"
        case (.modeAutomatic, "ru"):
            return "Авто"
        case (.modeAutomatic, "de"):
            return "Auto"
        case (.modeAutomatic, "es"):
            return "Auto"
        case (.modeAutomatic, "fr"):
            return "Auto"
        case (.modeAutomatic, "it"):
            return "Auto"
        case (.modeTwoD, "zh-Hans"):
            return "二维"
        case (.modeTwoD, "zh-Hant"):
            return "二維"
        case (.modeTwoD, "ja"):
            return "2D"
        case (.modeTwoD, "ru"):
            return "2D"
        case (.modeThreeD, "zh-Hans"):
            return "三维"
        case (.modeThreeD, "zh-Hant"):
            return "三維"
        case (.modeThreeD, "ja"):
            return "3D"
        case (.modeThreeD, "ru"):
            return "3D"
        case (.cameraFront, "zh-Hans"):
            return "前方"
        case (.cameraFront, "zh-Hant"):
            return "前方"
        case (.cameraFront, "ja"):
            return "前"
        case (.cameraFront, "ru"):
            return "Спереди"
        case (.cameraRear, "zh-Hans"):
            return "后方"
        case (.cameraRear, "zh-Hant"):
            return "後方"
        case (.cameraRear, "ja"):
            return "後ろ"
        case (.cameraRear, "ru"):
            return "Сзади"
        case (.cameraLeft, "zh-Hans"), (.cameraLeft, "zh-Hant"):
            return "左侧"
        case (.cameraLeft, "ja"):
            return "左"
        case (.cameraLeft, "ru"):
            return "Слева"
        case (.cameraRight, "zh-Hans"), (.cameraRight, "zh-Hant"):
            return "右侧"
        case (.cameraRight, "ja"):
            return "右"
        case (.cameraRight, "ru"):
            return "Справа"
        case (.cameraTop, "zh-Hans"):
            return "顶部"
        case (.cameraTop, "zh-Hant"):
            return "頂部"
        case (.cameraTop, "ja"):
            return "上"
        case (.cameraTop, "ru"):
            return "Сверху"
        case (.cameraFollow, "zh-Hans"):
            return "跟随"
        case (.cameraFollow, "zh-Hant"):
            return "跟隨"
        case (.cameraFollow, "ja"):
            return "追従"
        case (.cameraFollow, "ru"):
            return "Следом"
        case (.fallbackLowPower, "zh-Hans"):
            return "低电量模式，已回退到 2D"
        case (.fallbackLowPower, "zh-Hant"):
            return "低電量模式，已回退到 2D"
        case (.fallbackThermal, "zh-Hans"):
            return "设备温度较高，已回退到 2D"
        case (.fallbackThermal, "zh-Hant"):
            return "裝置溫度較高，已回退到 2D"
        case (.fallbackUnavailable, "zh-Hans"):
            return "3D 不可用，已回退到 2D"
        case (.fallbackUnavailable, "zh-Hant"):
            return "3D 不可用，已回退到 2D"
        default:
            switch key {
            case .modeAutomatic:
                return "Auto"
            case .modeTwoD:
                return "2D"
            case .modeThreeD:
                return "3D"
            case .cameraFront:
                return "Front"
            case .cameraRear:
                return "Rear"
            case .cameraLeft:
                return "Left"
            case .cameraRight:
                return "Right"
            case .cameraTop:
                return "Top"
            case .cameraFollow:
                return "Follow"
            case .fallbackLowPower:
                return "Low Power Mode: using 2D"
            case .fallbackThermal:
                return "Thermal pressure: using 2D"
            case .fallbackUnavailable:
                return "3D unavailable: using 2D"
            }
        }
    }
}
