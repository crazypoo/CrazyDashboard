//
//  PTPitWallManager.swift
//  CrazyDashboard
//
//  EN: Main-actor coordinator for the opt-in, LAN-only, read-only Pit Wall.
//  ES: Coordinador del actor principal para el Pit Wall opcional, local y de solo lectura.
//  中文：可选、仅局域网、只读 Pit Wall 的主线程协调器。
//

import Foundation
import Network
import Security
import Darwin

@MainActor
public final class PTPitWallManager: NSObject, PTVehicleTelemetryConsumer {
    public static let shared = PTPitWallManager()
    public static let didChange = Notification.Name("PTPitWallManager.didChange")

    public private(set) var isEnabled: Bool
    public private(set) var isRunning = false
    public private(set) var pairingURL: URL?
    public private(set) var lastError: String?

    private let listenerQueue = DispatchQueue(label: "com.yd.PTSpeed.pitwall.listener")
    private var listener: NWListener?
    private var servicePort: UInt16?
    private var token: String?
    private var sceneIsActive = false
    private var isObservingTelemetry = false
    private var rollingSeries = PTPitWallRollingSeries(maximumCount: 60)
    private var events: [PTPitWallEvent] = []
    private var latestSnapshot = PTPitWallSnapshot.empty
    private var lastSampleAt: Date?
    private var lastEventSignature: String?

    private override init() {
        isEnabled = PTMotoUserDefaultStruct.PTPitWallEnabled
        super.init()
    }

    public var pairingText: String? {
        if let pairingURL {
            return pairingURL.absoluteString
        }
        if let servicePort {
            return "PTSpeed Pit Wall · _pt-pitwall._tcp · \(servicePort)"
        }
        return nil
    }

    public func setSceneActive(_ active: Bool) {
        sceneIsActive = active
        if active, isEnabled {
            startIfEligible()
        } else {
            stopServer()
        }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        PTMotoUserDefaultStruct.PTPitWallEnabled = enabled
        if enabled, sceneIsActive {
            startIfEligible()
        } else if !enabled {
            stopServer()
        }
        notifyChange()
    }

    public func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        guard isRunning else { return }

        let connection = PTVehicleConnectivityCoordinator.shared.snapshot
        let control = connection.dashboard.state == .connected
            ? PTBluetoothServerManager.shared.latestControl
            : nil
        let twin = PTVehicleTwinStateMapper.make(
            unified: snapshot,
            connection: connection,
            control: control,
            now: Date()
        )
        let context = PTDashboardContextEngine.shared.snapshot.primaryContext.rawValue
        let now = Date()
        let coordinate = twin.coordinate.map {
            PTPitWallCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }

        if lastSampleAt.map({ now.timeIntervalSince($0) >= 0.25 }) ?? true {
            rollingSeries.append(
                PTPitWallSample(
                    capturedAt: now,
                    speedKmh: twin.speedKmh?.value,
                    rpm: twin.rpm.map { Int($0.value.rounded()) },
                    coordinate: coordinate
                )
            )
            lastSampleAt = now
        }

        let signature = [
            connection.dashboard.state.rawValue,
            connection.obd.state.rawValue,
            context
        ].joined(separator: "|")
        if lastEventSignature != signature {
            appendEvent(
                kind: "state_changed",
                context: "\(connectionLabel(connection)) · \(context)"
            )
            lastEventSignature = signature
        }

        latestSnapshot = PTPitWallSnapshot(
            generatedAt: now,
            updatedAt: snapshot.updatedAt,
            dashboardConnected: connection.dashboard.state == .connected,
            obdConnected: connection.obd.state == .connected,
            context: context,
            speedKmh: twin.speedKmh?.value,
            rpm: twin.rpm.map { Int($0.value.rounded()) },
            fuelPercent: twin.fuelPercent?.value,
            voltage: twin.voltage?.value,
            leanDegrees: twin.leanDegrees?.value,
            tcsState: twin.tcsState?.value.rawValue,
            absState: twin.absState?.value.rawValue,
            kickstandDown: twin.kickstandDown?.value,
            engineState: twin.engineState?.value.rawValue,
            freshness: twin.freshness.rawValue,
            isSynthetic: twin.isSynthetic,
            coordinate: coordinate,
            samples: rollingSeries.samples,
            events: events
        )
    }

    private func startIfEligible() {
        guard isEnabled, sceneIsActive, listener == nil else { return }

        lastError = nil
        token = makeToken()
        rollingSeries = PTPitWallRollingSeries(maximumCount: 60)
        events.removeAll(keepingCapacity: true)
        latestSnapshot = .empty
        lastSampleAt = nil
        lastEventSignature = nil

        PTVehicleTelemetryBridge.shared.startIfNeeded()
        PTDashboardContextEngine.shared.start()
        PTVehicleTelemetryConsumerHub.shared.register(self)
        isObservingTelemetry = true

        do {
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .wifi
            let newListener = try NWListener(using: parameters)
            let queue = listenerQueue
            newListener.service = NWListener.Service(name: "PTSpeed Pit Wall", type: "_pt-pitwall._tcp")
            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: queue)
                Task { @MainActor [weak self] in
                    self?.receive(on: connection)
                }
            }
            listener = newListener
            newListener.start(queue: queue)
        } catch {
            lastError = "listener_creation_failed"
            stopServer(clearError: false)
            notifyChange()
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            servicePort = listener?.port?.rawValue
            pairingURL = makePairingURL()
            isRunning = true
            appendEvent(kind: "server_ready", context: "LAN-only read-only")
            notifyChange()
        case .failed(let error):
            lastError = String(describing: error)
            stopServer(clearError: false)
            notifyChange()
        case .cancelled:
            isRunning = false
        case .setup, .waiting:
            break
        @unknown default:
            break
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: PTPitWallHTTPRequest.maximumRequestBytes
        ) { [weak self] data, _, _, _ in
            guard let data else {
                connection.cancel()
                return
            }
            Task { @MainActor [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                let response = self.response(for: data)
                connection.send(content: response.data(), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }

    private func response(for data: Data) -> PTPitWallHTTPResponse {
        guard let request = PTPitWallHTTPRequest.parse(data),
              let token,
              request.token == token else {
            return .unauthorized()
        }

        switch request.path {
        case "/":
            return PTPitWallHTTPResponse(
                statusCode: 200,
                reason: "OK",
                contentType: "text/html; charset=utf-8",
                body: PTPitWallWebUI.html(token: token),
                headers: [
                    "Content-Security-Policy": "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'"
                ]
            )
        case "/api/snapshot", "/api/events":
            do {
                return .json(try PTPitWallSnapshotSerializer.data(from: latestSnapshot))
            } catch {
                return .text("Serialization failed", statusCode: 500, reason: "Internal Server Error")
            }
        default:
            return .notFound()
        }
    }

    private func stopServer(clearError: Bool = true) {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        servicePort = nil
        pairingURL = nil
        token = nil
        isRunning = false
        rollingSeries = PTPitWallRollingSeries(maximumCount: 60)
        events.removeAll(keepingCapacity: false)
        latestSnapshot = .empty
        lastSampleAt = nil
        lastEventSignature = nil
        if isObservingTelemetry {
            PTVehicleTelemetryConsumerHub.shared.unregister(self)
            PTDashboardContextEngine.shared.stop()
            isObservingTelemetry = false
        }
        if clearError {
            lastError = nil
        }
        notifyChange()
    }

    private func appendEvent(kind: String, context: String) {
        events.append(PTPitWallEvent(occurredAt: Date(), kind: kind, context: context))
        if events.count > 24 {
            events.removeFirst(events.count - 24)
        }
    }

    private func connectionLabel(_ snapshot: PTVehicleSnapshot) -> String {
        let dashboard = snapshot.dashboard.state == .connected ? "dashboard" : "dashboard_offline"
        let obd = snapshot.obd.state == .connected ? "obd" : "obd_offline"
        return "\(dashboard),\(obd)"
    }

    private func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func makePairingURL() -> URL? {
        guard let servicePort, let token,
              let address = PTPitWallNetworkAddress.localWiFiIPv4() else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = address
        components.port = Int(servicePort)
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

private enum PTPitWallNetworkAddress {
    static func localWiFiIPv4() -> String? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return nil }
        defer { freeifaddrs(addressList) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let name = String(cString: interface.ifa_name)
            guard flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  name == "en0" || name == "en1",
                  let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else {
                pointer = interface.ifa_next
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                return String(cString: host)
            }
            pointer = interface.ifa_next
        }
        return nil
    }
}
