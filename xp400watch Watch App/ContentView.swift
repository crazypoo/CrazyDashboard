//
//  ContentView.swift
//  xp400watch Watch App
//
//  EN: Read-only motorcycle status, navigation prompts and parking finder.
//  ES: Estado de la motocicleta, avisos de navegación y buscador de estacionamiento de solo lectura.
//  中文：只读展示摩托车状态、导航提示和停车寻车入口。
//

import SwiftUI

struct ContentView: View {
    @StateObject private var statusStore = PTWatchStatusStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PTWatchVehicleStatusView(status: statusStore.status)
                PTWatchReadinessView(readiness: statusStore.readiness)
                PTWatchNavigationView(navigation: statusStore.navigation)
                PTWatchParkingView(status: statusStore.status)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.1).ignoresSafeArea())
    }
}

// EN: This card mirrors the iPhone's cached departure check and stays read-only on Watch.
// ES: Esta tarjeta refleja la comprobación de salida almacenada en el iPhone y permanece en solo lectura.
// 中文：此卡片复用 iPhone 缓存的出发检查结果，并且在 Watch 上保持只读。
private struct PTWatchReadinessView: View {
    let readiness: PTWatchReadinessStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .foregroundStyle(stateColor)
                Text("ride_readiness")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(stateTitle)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }

            if readiness.updatedAt == .distantPast {
                Text("ride_readiness_unavailable_hint")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            } else if readiness.issues.isEmpty {
                Text("ride_readiness_ready_hint")
                    .font(.caption2)
                    .foregroundStyle(.gray)
            } else {
                ForEach(Array(readiness.issues.prefix(2)), id: \.rawValue) { issue in
                    Label(issueTitle(for: issue), systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var stateTitle: LocalizedStringKey {
        switch readiness.state {
        case .ready: return "ride_readiness_ready"
        case .attention: return "ride_readiness_attention"
        case .unavailable: return "ride_readiness_unavailable"
        }
    }

    private var stateColor: Color {
        switch readiness.state {
        case .ready: return .green
        case .attention: return .orange
        case .unavailable: return .gray
        }
    }

    private var iconName: String {
        switch readiness.state {
        case .ready: return "checkmark.shield.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .unavailable: return "questionmark.circle"
        }
    }

    private func issueTitle(for issue: PTWatchReadinessIssue) -> LocalizedStringKey {
        switch issue {
        case .dashboardDisconnected: return "ride_readiness_issue_dashboard"
        case .obdDisconnected: return "ride_readiness_issue_obd"
        case .lowFuel: return "ride_readiness_issue_fuel"
        case .rangeUnavailable: return "ride_readiness_issue_range"
        case .maintenanceRequired: return "ride_readiness_issue_maintenance"
        case .batteryLow: return "ride_readiness_issue_battery"
        case .staleData: return "ride_readiness_issue_stale"
        case .pttLocationSharingDisabled: return "ride_readiness_issue_ptt"
        }
    }
}

private struct PTWatchVehicleStatusView: View {
    let status: PTWidgetSharedStatus
    private let mainColor = Color(red: 0.2, green: 0.6, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: status.isConnected ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                        .foregroundStyle(status.isConnected ? .green : .gray)
                    Text(connectionTitle)
                        .font(.headline)
                        .foregroundStyle(status.isConnected ? .green : .gray)
                }

                Spacer(minLength: 4)

                Group {
                    if status.lastUpdateTime == .distantPast {
                        Text("ride_not_available")
                    } else {
                        Text(status.lastUpdateTime, style: .time)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.trailing)
            }

            Divider().overlay(Color.gray.opacity(0.3))

            HStack(spacing: 14) {
                PTWatchMetricView(
                    title: "watch_assistant_fuel_level",
                    value: "\(status.fuelLevel)%",
                    systemImage: "fuelpump.fill",
                    color: mainColor
                )
                PTWatchMetricView(
                    title: "casa_card_little_trip",
                    value: String(format: "%.1f km", status.tripKm),
                    systemImage: "flag.checkered",
                    color: mainColor
                )
            }
        }
    }

    private var connectionTitle: LocalizedStringKey {
        status.isConnected ? "ride_connected" : "ride_disconnected"
    }
}

private struct PTWatchMetricView: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.gray)
                .symbolRenderingMode(.hierarchical)
                .tint(color)
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PTWatchNavigationView: View {
    let navigation: PTWatchRideAssistantState
    private let mainColor = Color(red: 0.2, green: 0.6, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: navigation.maneuver.symbolName)
                    .foregroundStyle(mainColor)
                Text("watch_assistant_title")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Text(sourceTitle)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }

            if !navigation.status.isVisible {
                Text("watch_assistant_no_navigation")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            } else if !navigation.isFresh {
                Label("watch_assistant_stale", systemImage: "clock.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 6) {
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if navigation.totalSteps > 0 {
                        Text("\(navigation.currentStep)/\(navigation.totalSteps)")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                    }
                }

                if !navigation.routeName.isEmpty {
                    Text(navigation.routeName)
                        .font(.caption2)
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }

                if navigation.instruction.isEmpty {
                    Text("watch_assistant_no_instruction")
                        .font(.headline)
                        .foregroundStyle(.white)
                } else {
                    Text(navigation.instruction)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 10) {
                    PTWatchDistanceView(
                        title: "watch_assistant_distance_to_turn",
                        meters: navigation.distanceToManeuverMeters,
                        color: mainColor
                    )
                    PTWatchDistanceView(
                        title: "watch_assistant_remaining",
                        meters: navigation.distanceToDestinationMeters,
                        color: .white
                    )
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var sourceTitle: LocalizedStringKey {
        switch navigation.source {
        case .roadbook:
            return "roadbook_title"
        case .turnByTurn:
            return "watch_assistant_turn_by_turn"
        case .none:
            return "watch_assistant_title"
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch navigation.status {
        case .active:
            return "roadbook_status_active"
        case .paused:
            return "roadbook_status_paused"
        case .offRoute:
            return "roadbook_status_off_route"
        case .completed:
            return "roadbook_status_completed"
        case .rerouting:
            return "watch_assistant_rerouting"
        case .searchingGPS:
            return "watch_assistant_searching_gps"
        case .idle:
            return "watch_assistant_no_navigation"
        }
    }

    private var statusColor: Color {
        switch navigation.status {
        case .offRoute, .rerouting, .searchingGPS:
            return .orange
        case .completed, .active:
            return .green
        case .paused:
            return .yellow
        case .idle:
            return .gray
        }
    }
}

private struct PTWatchDistanceView: View {
    let title: LocalizedStringKey
    let meters: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.gray)
            Text(Self.formattedDistance(meters))
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func formattedDistance(_ meters: Double) -> String {
        let safeMeters = meters.isFinite ? max(0, meters) : 0
        if safeMeters >= 1_000 {
            return String(format: "%.1f km", safeMeters / 1_000)
        }
        return String(format: "%.0f m", safeMeters)
    }
}

private struct PTWatchParkingView: View {
    let status: PTWidgetSharedStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Divider().overlay(Color.gray.opacity(0.3))

            Label("ride_parking", systemImage: "parkingsign.circle.fill")
                .font(.caption)
                .foregroundStyle(.gray)
                .symbolRenderingMode(.hierarchical)
                .tint(.orange)

            if hasParkingLocation {
                Text(status.address)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let mapURL = parkingMapURL {
                Link(destination: mapURL) {
                    Label("watch_assistant_find_motorcycle", systemImage: "map.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else {
                Label("ride_no_parking", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }

    private var hasParkingLocation: Bool {
        guard status.lastUpdateTime != .distantPast else { return false }
        return status.parkedLat.isFinite && status.parkedLon.isFinite &&
            (abs(status.parkedLat) > 0.000001 || abs(status.parkedLon) > 0.000001)
    }

    private var parkingMapURL: URL? {
        guard hasParkingLocation else { return nil }

        var components = URLComponents()
        components.scheme = "http"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(status.parkedLat),\(status.parkedLon)"),
            URLQueryItem(
                name: "q",
                value: status.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Motorcycle"
                    : status.address
            )
        ]
        return components.url
    }
}

#Preview {
    ContentView()
}
