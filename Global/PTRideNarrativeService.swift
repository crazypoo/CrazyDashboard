//
//  PTRideNarrativeService.swift
//  CrazyDashboard
//
//  EN: User-triggered ride prose with a deterministic offline fallback.
//  ES: Texto de ruta solicitado por el usuario con un respaldo determinista sin conexión.
//  中文：用户主动触发的骑行文字总结，始终提供确定性的离线回退。
//

import Foundation
import PooTools

#if canImport(FoundationModels)
import FoundationModels
#endif

// EN: The service receives only aggregate ride facts, never VINs, coordinates or BLE payloads.
// ES: El servicio solo recibe hechos agregados de la ruta, nunca VIN, coordenadas ni cargas BLE.
// 中文：服务只接收骑行聚合数据，不接收 VIN、坐标或 BLE 载荷。
@MainActor
public final class PTRideNarrativeService {
    public static let shared = PTRideNarrativeService()

    private init() {}

    public func makeNarrative(for summary: PTRideStorySummary) async -> String {
        let fallback = Self.fallback(for: summary)

#if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.availability == .available,
                  model.supportsLocale(PTLanguage.share.locale) else {
                return fallback
            }

            let instructions = """
            You write a concise, factual motorcycle ride summary. Use the requested locale. \
            Never invent places, weather, vehicle faults, or safety conclusions. \
            Use at most three short sentences.
            """
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: prompt(for: summary))
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, text.count <= 600 {
                    return text
                }
            } catch {
                PTNSLogConsole("ℹ️ [骑行回顾] Foundation Models 不可用，使用本地回退: \(error.localizedDescription)")
            }
        }
#endif

        return fallback
    }

    // EN: This fallback is stable on iOS 17 and is also used when the on-device model is unavailable.
    // ES: Este respaldo es estable en iOS 17 y también se usa cuando el modelo del dispositivo no está disponible.
    // 中文：该回退在 iOS 17 上稳定可用，端侧模型不可用时也会使用它。
    public static func fallback(for summary: PTRideStorySummary) -> String {
        let distance = PTDashboardConfig.shared.appShowMileageValueString(summary.distanceKm)
            + PTDashboardConfig.shared.appShowUniLabel
        let averageSpeed = PTDashboardConfig.shared.appShowMileageValueString(summary.averageSpeedKmh)
            + PTDashboardConfig.shared.appShowUniLabel
        let maxSpeed = PTDashboardConfig.shared.appShowMileageValueString(summary.maxSpeedKmh)
            + PTDashboardConfig.shared.appShowUniLabel
        return PTDashboardConfig.language(
            key: "ride_story_narrative_fallback",
            distance,
            averageSpeed,
            maxSpeed,
            summary.eventCount
        )
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func prompt(for summary: PTRideStorySummary) -> String {
        """
        Locale: \(PTLanguage.share.locale.identifier)
        Distance km: \(summary.distanceKm)
        Duration minutes: \(summary.durationMinutes)
        Average speed km/h: \(summary.averageSpeedKmh)
        Maximum speed km/h: \(summary.maxSpeedKmh)
        Maximum lean angle degrees: \(summary.maximumLeanAngle)
        Review event count: \(summary.eventCount)
        Off-road event count: \(summary.offRoadEventCount)
        Elevation gain meters: \(summary.elevationGainMeters)
        """
    }
#endif
}
