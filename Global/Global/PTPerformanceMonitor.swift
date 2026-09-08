//
//  PTPerformanceMonitor.swift
//  CrazyDashboard
//
//  EN: Small native diagnostics bridge for measuring the app without collecting vehicle content.
//  ES: Puente pequeño y nativo para medir la app sin recopilar contenido del vehículo.
//  中文：使用系统能力进行轻量性能诊断，不收集车辆内容。
//

import Foundation
import MetricKit
import os.log
import os.signpost

// EN: MetricKit reports aggregate health data; it is never used as a vehicle telemetry source.
// ES: MetricKit informa datos de salud agregados; nunca se usa como fuente de telemetría del vehículo.
// 中文：MetricKit 只报告聚合健康数据，绝不作为车辆遥测来源。
public final class PTPerformanceMonitor: NSObject, MXMetricManagerSubscriber {
    public static let shared = PTPerformanceMonitor()

    private let log = OSLog(subsystem: "com.yd.PTSpeed", category: "Performance")
    private let stateLock = NSLock()
    private var isRegistered = false

    private override init() {
        super.init()
    }

    public func start() {
        stateLock.lock()
        guard !isRegistered else {
            stateLock.unlock()
            return
        }
        isRegistered = true
        stateLock.unlock()
        MXMetricManager.shared.add(self)
    }

    public func stop() {
        stateLock.lock()
        guard isRegistered else {
            stateLock.unlock()
            return
        }
        isRegistered = false
        stateLock.unlock()
        MXMetricManager.shared.remove(self)
    }

    public func begin(_ name: StaticString) -> OSSignpostID {
        let identifier = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: identifier)
        return identifier
    }

    public func end(_ name: StaticString, identifier: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: identifier)
    }

    public func didReceive(_ payloads: [MXMetricPayload]) {
        os_log(
            "MetricKit received %d metric payload(s)",
            log: log,
            type: .info,
            payloads.count
        )
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        os_log(
            "MetricKit received %d diagnostic payload(s)",
            log: log,
            type: .info,
            payloads.count
        )
    }
}
