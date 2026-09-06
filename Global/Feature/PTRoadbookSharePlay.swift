//
//  PTRoadbookSharePlay.swift
//  CrazyDashboard
//
//  EN: SharePlay collaboration for a bounded, read-only Roadbook snapshot.
//  ES: Colaboración SharePlay para una instantánea limitada y de solo lectura del Roadbook.
//  中文：使用 SharePlay 共享有界、只读的 Roadbook 快照。
//

import Foundation
import GroupActivities
import UIKit

nonisolated public struct PTRoadbookShareSnapshot: Codable, Equatable, Sendable {
    public let roadbookID: UUID
    public let name: String
    public let coordinateSystem: PTRoadbookCoordinateSystem
    public let waypoints: [PTCruiseWaypoint]

    public init(roadbook: PTRoadbook) {
        roadbookID = roadbook.id
        name = String(roadbook.name.prefix(120))
        coordinateSystem = roadbook.coordinateSystem
        waypoints = Array(roadbook.waypoints.prefix(64))
    }
}

// EN: The activity carries route context only; it never carries BLE commands, private telemetry or credentials.
// ES: La actividad solo transporta contexto de ruta; nunca transporta comandos BLE, telemetría privada ni credenciales.
// 中文：该活动仅传递路线上下文，不传输 BLE 指令、私有遥测或凭据。
@available(iOS 17.0, *)
nonisolated struct PTRoadbookShareActivity: GroupActivity {
    let snapshot: PTRoadbookShareSnapshot

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = snapshot.name
        metadata.subtitle = "Roadbook"
        metadata.type = .exploreTogether
        metadata.fallbackURL = URL(string: "xp400://action/openroadbooks?id=\(snapshot.roadbookID.uuidString)")
        return metadata
    }
}

// EN: This manager keeps SharePlay optional and leaves ordinary Roadbook navigation unchanged.
// ES: Este gestor mantiene SharePlay como función opcional y no cambia la navegación normal del Roadbook.
// 中文：该管理器将 SharePlay 保持为可选能力，不影响普通 Roadbook 导航。
@available(iOS 17.0, *)
@MainActor
final class PTSharePlayRoadbookManager {
    static let shared = PTSharePlayRoadbookManager()
    static let snapshotDidReceive = Notification.Name("PTSharePlayRoadbookSnapshotDidReceive")

    private var sessionTask: Task<Void, Never>?
    private var receiveTasks: [UUID: Task<Void, Never>] = [:]
    private(set) var latestReceivedSnapshot: PTRoadbookShareSnapshot?

    private init() {
        startListening()
    }

    func share(roadbook: PTRoadbook, from presenter: UIViewController) {
        let activity = PTRoadbookShareActivity(snapshot: PTRoadbookShareSnapshot(roadbook: roadbook))
        Task { @MainActor [weak self, weak presenter] in
            guard let self else { return }
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                do {
                    _ = try await activity.activate()
                } catch {
                    self.presentStatus(
                        key: "roadbook_shareplay_unavailable",
                        presenter: presenter
                    )
                }
            case .activationDisabled, .cancelled:
                self.presentStatus(
                    key: "roadbook_shareplay_unavailable",
                    presenter: presenter
                )
            @unknown default:
                self.presentStatus(
                    key: "roadbook_shareplay_unavailable",
                    presenter: presenter
                )
            }
        }
    }

    private func startListening() {
        guard sessionTask == nil else { return }
        sessionTask = Task { @MainActor [weak self] in
            for await session in PTRoadbookShareActivity.sessions() {
                guard let self else { return }
                self.configure(session)
            }
        }
    }

    private func configure(_ session: GroupSession<PTRoadbookShareActivity>) {
        session.join()
        let messenger = GroupSessionMessenger(session: session)
        let receiveTask = Task { @MainActor [weak self, weak session] in
            for await (snapshot, _) in messenger.messages(of: PTRoadbookShareSnapshot.self) {
                guard let self else { return }
                self.latestReceivedSnapshot = snapshot
                NotificationCenter.default.post(
                    name: Self.snapshotDidReceive,
                    object: snapshot
                )
            }
            session?.leave()
        }
        receiveTasks[session.id] = receiveTask

        Task { @MainActor in
            try? await messenger.send(session.activity.snapshot)
        }
    }

    private func presentStatus(key: String, presenter: UIViewController?) {
        guard let presenter else { return }
        let alert = UIAlertController(
            title: PTDashboardConfig.languageFunc(text: "roadbook_shareplay"),
            message: PTDashboardConfig.languageFunc(text: key),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: PTDashboardConfig.languageFunc(text: "button_confirm"),
            style: .default
        ))
        presenter.present(alert, animated: true)
    }

    deinit {
        sessionTask?.cancel()
        receiveTasks.values.forEach { $0.cancel() }
    }
}
