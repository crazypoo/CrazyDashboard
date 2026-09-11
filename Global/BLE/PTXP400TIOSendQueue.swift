//
//  PTXP400TIOSendQueue.swift
//  CrazyDashboard
//
//  EN: Keeps TIO jobs ordered and lets the manager replace only stale navigation jobs.
//  ES: Mantiene ordenados los trabajos TIO y permite reemplazar solo la navegación obsoleta.
//  中文：维护 TIO 任务顺序，并允许管理器只替换过期的导航任务。
//

import CoreBluetooth
import Foundation

/// EN: Queue storage is deliberately small; CoreBluetooth remains owned by the manager.
/// ES: El almacenamiento de la cola es deliberadamente pequeño; el gestor sigue siendo dueño de CoreBluetooth.
/// 中文：队列存储保持精简，CoreBluetooth 仍由管理器拥有。
final class PTXP400TIOSendQueue {
    enum Kind {
        case regular
        case navigation
    }

    struct Job {
        typealias Kind = PTXP400TIOSendQueue.Kind
        let data: Data
        let characteristic: CBMutableCharacteristic
        let kind: Kind
        let completion: (() -> Void)?
    }

    private(set) var jobs: [Job] = []

    var isEmpty: Bool { jobs.isEmpty }
    var first: Job? { jobs.first }

    func append(_ job: Job) {
        jobs.append(job)
    }

    @discardableResult
    func removeFirst() -> Job {
        jobs.removeFirst()
    }

    func removeAll(keepingCapacity: Bool) {
        jobs.removeAll(keepingCapacity: keepingCapacity)
    }

    func removeAll(where shouldRemove: (Job) throws -> Bool) rethrows {
        try jobs.removeAll(where: shouldRemove)
    }
}
