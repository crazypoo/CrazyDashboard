//
//  PTJieliSDKBridge.swift
//  PTSpeed
//
//  EN: Keeps the Jieli 2.5.0 boundary limited to SDK configuration and callbacks.
//  ES: Mantiene el límite de Jieli 2.5.0 limitado a configuración del SDK y callbacks.
//  中文：将 Jieli 2.5.0 边界限制在 SDK 配置和回调转换。
//

import Foundation

@MainActor
public final class PTJieliSDKBridge {
    public var isAvailable: Bool { engine.isAvailable }

    private let engine: PTJieliOTAEngine

    public init(engine: PTJieliOTAEngine) {
        self.engine = engine
    }

    // EN: Create the SDK engine inside the main-actor initializer, not in a default argument expression.
    // ES: Crea el motor del SDK dentro del inicializador del actor principal, no en una expresión de argumento predeterminada.
    // 中文：在主 actor 初始化器内部创建 SDK 引擎，避免在默认参数表达式中跨 actor 初始化。
    public convenience init() {
        self.init(engine: PTJieliSDKOTAEngine())
    }

    public func start(
        firmwareData: Data,
        transport: PTJieliBLETransport,
        discovery: PTJieliBLETransportDiscovery,
        progress: @escaping PTJieliOTAProgressHandler,
        event: @escaping PTJieliOTAEventHandler,
        reconnect: @escaping PTJieliOTAReconnectHandler
    ) async throws {
        try await engine.startOTA(
            firmwareData: firmwareData,
            transport: transport,
            discovery: discovery,
            progress: progress,
            event: event,
            reconnect: reconnect
        )
    }

    public func cancel() {
        engine.cancelOTA()
    }
}
