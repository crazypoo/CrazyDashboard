//
//  PTRideGroupSafety.swift
//  CrazyDashboard
//
//  EN: Read-only group safety analysis layered over the existing PTT location packets.
//  ES: Análisis de seguridad de grupo de solo lectura sobre los paquetes PTT existentes.
//  中文：基于现有 PTT 位置包的只读组队安全分析。
//

import Foundation
import CoreLocation
import MultipeerConnectivity

nonisolated public struct PTRideCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    nonisolated public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) &&
            (latitude != 0 || longitude != 0)
    }
}

public struct PTRidePeerLocationSample: Codable, Equatable, Sendable {
    public let peerID: String
    public let displayName: String
    public let coordinate: PTRideCoordinate
    public let speedKmh: Double
    public let course: Double
    public let updatedAt: Date

    public init(
        peerID: String,
        displayName: String,
        coordinate: PTRideCoordinate,
        speedKmh: Double,
        course: Double,
        updatedAt: Date
    ) {
        self.peerID = peerID
        self.displayName = displayName
        self.coordinate = coordinate
        self.speedKmh = max(speedKmh.isFinite ? speedKmh : 0, 0)
        self.course = course.isFinite ? course : 0
        self.updatedAt = updatedAt
    }
}

public enum PTRidePeerSafetyState: String, Codable, Sendable {
    case connected
    case tooFar
    case stale
    case noLocation
}

public struct PTRidePeerSafetyStatus: Codable, Equatable, Sendable {
    public let peerID: String
    public let displayName: String
    public let state: PTRidePeerSafetyState
    public let distanceMeters: Double?
    public let locationAgeSeconds: TimeInterval?

    public init(
        peerID: String,
        displayName: String,
        state: PTRidePeerSafetyState,
        distanceMeters: Double?,
        locationAgeSeconds: TimeInterval?
    ) {
        self.peerID = peerID
        self.displayName = displayName
        self.state = state
        self.distanceMeters = distanceMeters
        self.locationAgeSeconds = locationAgeSeconds
    }
}

public struct PTRideGroupSafetySnapshot: Codable, Equatable, Sendable {
    public let isGroupActive: Bool
    public let generatedAt: Date
    public let peers: [PTRidePeerSafetyStatus]

    public init(isGroupActive: Bool, generatedAt: Date, peers: [PTRidePeerSafetyStatus]) {
        self.isGroupActive = isGroupActive
        self.generatedAt = generatedAt
        self.peers = peers
    }

    public static let inactive = PTRideGroupSafetySnapshot(
        isGroupActive: false,
        generatedAt: .distantPast,
        peers: []
    )

    public var stalePeerCount: Int {
        peers.count(where: { $0.state == .stale })
    }

    public var tooFarPeerCount: Int {
        peers.count(where: { $0.state == .tooFar })
    }

    public var noLocationPeerCount: Int {
        peers.count(where: { $0.state == .noLocation })
    }

    public var hasAlert: Bool {
        stalePeerCount > 0 || tooFarPeerCount > 0 || noLocationPeerCount > 0
    }
}

public struct PTRideGroupSafetyPolicy: Sendable {
    public let staleAfterSeconds: TimeInterval
    public let tooFarDistanceMeters: CLLocationDistance

    public init(staleAfterSeconds: TimeInterval = 15, tooFarDistanceMeters: CLLocationDistance = 800) {
        self.staleAfterSeconds = max(staleAfterSeconds, 1)
        self.tooFarDistanceMeters = max(tooFarDistanceMeters, 1)
    }

    public static let `default` = PTRideGroupSafetyPolicy()
}

public enum PTRideGroupSafetyAnalyzer {
    /// EN: Classify only connected peers; missing telemetry is reported as unknown, never as a crash or false location.
    /// ES: Clasifica solo a los compañeros conectados; la telemetría ausente se informa como desconocida.
    /// 中文：只分析当前已连接成员；缺失遥测报告为未知，不伪造位置也不崩溃。
    public static func analyze(
        activePeerIDs: [String],
        samples: [String: PTRidePeerLocationSample],
        localCoordinate: PTRideCoordinate?,
        now: Date,
        policy: PTRideGroupSafetyPolicy = .default
    ) -> PTRideGroupSafetySnapshot {
        let uniquePeerIDs = Array(Set(activePeerIDs)).sorted()
        let statuses = uniquePeerIDs.map { peerID -> PTRidePeerSafetyStatus in
            guard let sample = samples[peerID] else {
                return PTRidePeerSafetyStatus(
                    peerID: peerID,
                    displayName: peerID,
                    state: .noLocation,
                    distanceMeters: nil,
                    locationAgeSeconds: nil
                )
            }

            let age = max(now.timeIntervalSince(sample.updatedAt), 0)
            if age > policy.staleAfterSeconds {
                return PTRidePeerSafetyStatus(
                    peerID: peerID,
                    displayName: sample.displayName,
                    state: .stale,
                    distanceMeters: distanceMeters(from: localCoordinate, to: sample.coordinate),
                    locationAgeSeconds: age
                )
            }

            let distance = distanceMeters(from: localCoordinate, to: sample.coordinate)
            let state: PTRidePeerSafetyState = distance.map { $0 > policy.tooFarDistanceMeters } == true
                ? .tooFar
                : .connected
            return PTRidePeerSafetyStatus(
                peerID: peerID,
                displayName: sample.displayName,
                state: state,
                distanceMeters: distance,
                locationAgeSeconds: age
            )
        }

        return PTRideGroupSafetySnapshot(
            isGroupActive: !uniquePeerIDs.isEmpty,
            generatedAt: now,
            peers: statuses
        )
    }

    private static func distanceMeters(
        from localCoordinate: PTRideCoordinate?,
        to peerCoordinate: PTRideCoordinate
    ) -> Double? {
        guard let localCoordinate,
              localCoordinate.isValid,
              peerCoordinate.isValid else { return nil }
        let localLocation = CLLocation(latitude: localCoordinate.latitude, longitude: localCoordinate.longitude)
        let peerLocation = CLLocation(latitude: peerCoordinate.latitude, longitude: peerCoordinate.longitude)
        return localLocation.distance(from: peerLocation)
    }
}

@MainActor
public final class PTRideGroupSafetyCoordinator {
    public static let shared = PTRideGroupSafetyCoordinator()
    public static let snapshotDidChange = Notification.Name("PTRideGroupSafetyCoordinator.snapshotDidChange")

    public private(set) var snapshot: PTRideGroupSafetySnapshot = .inactive

    private var observerTokens: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var peerSamples: [String: PTRidePeerLocationSample] = [:]
    private var isStarted = false

    private init() {}

    public func start() {
        guard !isStarted else {
            refresh()
            return
        }
        isStarted = true
        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(
            forName: PTPeerLocationDidUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let peer = notification.userInfo?["peerID"] as? MCPeerID,
                  let location = notification.userInfo?["location"] as? PTPeerLocation,
                  (-90...90).contains(location.lat),
                  (-180...180).contains(location.lon) else { return }
            let sample = PTRidePeerLocationSample(
                peerID: peer.displayName,
                displayName: peer.displayName,
                coordinate: PTRideCoordinate(latitude: location.lat, longitude: location.lon),
                speedKmh: location.speed,
                course: location.course,
                updatedAt: Date()
            )
            Task { @MainActor [weak self, sample] in
                self?.handlePeerLocation(sample)
            }
        })
        observerTokens.append(center.addObserver(
            forName: PTIntercomGlobalStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        })
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        observerTokens.forEach(NotificationCenter.default.removeObserver)
        observerTokens.removeAll()
        peerSamples.removeAll()
        publish(.inactive)
    }

    private func handlePeerLocation(_ sample: PTRidePeerLocationSample) {
        guard isStarted else { return }
        peerSamples[sample.peerID] = sample
        refresh()
    }

    private func refresh() {
        guard isStarted else { return }
        let manager = PTLocalIntercomManager.shared
        let activePeerIDs = manager.activePeers.map(\.displayName)
        let activeSet = Set(activePeerIDs)
        peerSamples = peerSamples.filter { activeSet.contains($0.key) }
        let localLocation = PTLocationEngine.shared.lastLocation
        let localCoordinate = localLocation.map {
            PTRideCoordinate(
                latitude: $0.coordinate.latitude,
                longitude: $0.coordinate.longitude
            )
        }
        let next = PTRideGroupSafetyAnalyzer.analyze(
            activePeerIDs: activePeerIDs,
            samples: peerSamples,
            localCoordinate: localCoordinate,
            now: Date()
        )
        guard next != snapshot else { return }
        publish(next)
    }

    private func publish(_ next: PTRideGroupSafetySnapshot) {
        snapshot = next
        NotificationCenter.default.post(name: Self.snapshotDidChange, object: next)
    }

    deinit {
        refreshTimer?.invalidate()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }
}
