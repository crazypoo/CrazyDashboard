//
//  PTVehicleTelemetryConsumer.swift
//  CrazyDashboard
//
//  EN: Provides one actor-safe, read-only delivery boundary for vehicle telemetry consumers.
//  ES: Proporciona un límite de entrega de solo lectura y seguro entre actores para los consumidores.
//  中文：为车辆遥测消费者提供统一、只读且安全跨 actor 的交付边界。
//

import Foundation

@MainActor
public protocol PTVehicleTelemetryConsumer: AnyObject {
    func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot)
}

// EN: The hub keeps the latest immutable snapshot so late-created CarPlay and dashboard views render immediately.
// ES: El concentrador conserva la última instantánea inmutable para que las vistas tardías se actualicen de inmediato.
// 中文：Hub 保存最近一次不可变快照，保证晚创建的 CarPlay 和仪表页面可以立即刷新。
@MainActor
public final class PTVehicleTelemetryConsumerHub {
    public static let shared = PTVehicleTelemetryConsumerHub()

    public private(set) var latestSnapshot: PTUnifiedVehicleTelemetrySnapshot = .empty

    private let consumers = NSHashTable<AnyObject>.weakObjects()

    private init() {}

    public func register(_ consumer: PTVehicleTelemetryConsumer) {
        consumers.add(consumer)
        consumer.vehicleTelemetryDidUpdate(latestSnapshot)
    }

    public func unregister(_ consumer: PTVehicleTelemetryConsumer) {
        consumers.remove(consumer)
    }

    public func publish(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        latestSnapshot = snapshot
        for object in consumers.allObjects {
            (object as? PTVehicleTelemetryConsumer)?.vehicleTelemetryDidUpdate(snapshot)
        }
    }

    public func reset() {
        publish(.empty)
    }
}

