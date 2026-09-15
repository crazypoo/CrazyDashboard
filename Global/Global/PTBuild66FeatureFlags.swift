//
//  PTBuild66FeatureFlags.swift
//  CrazyDashboard
//
//  EN: Keeps the temporary Build 66 rollback switch in one MainActor-owned place.
//  ES: Mantiene el interruptor temporal de rollback de Build 66 en un único lugar propiedad de MainActor.
//  中文：将 Build 66 临时回滚开关集中放在 MainActor 所有的单一位置。
//

import Foundation

@MainActor
public enum PTBuild66FeatureFlags {
    // EN: This is an internal validation switch; it is not exposed in user settings.
    // ES: Este interruptor es solo para validación interna; no se expone en los ajustes del usuario.
    // 中文：这是内部验证开关，不暴露给普通用户设置。
    public static var gpsSpeedFallbackEnabled = true
}
