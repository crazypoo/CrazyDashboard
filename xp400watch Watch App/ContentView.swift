//
//  ContentView.swift
//  xp400watch Watch App
//
//  Created by 邓杰豪 on 21/8/2026.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var statusStore = PTWatchStatusStore()

    var body: some View {
        PTWatchStatusView(status: statusStore.status)
    }
}

private struct PTWatchStatusView: View {
    let status: PTWidgetSharedStatus
    private let mainColor = Color(red: 0.2, green: 0.6, blue: 1.0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: status.isConnected ? "wave.3.right.circle.fill" : "wave.3.right.circle")
                            .foregroundStyle(status.isConnected ? .green : .gray)
                        Text(status.isConnected ? "机车已连接" : "机车已断开")
                            .font(.headline)
                            .foregroundStyle(status.isConnected ? .green : .gray)
                    }

                    Spacer(minLength: 4)

                    Group {
                        if status.lastUpdateTime == .distantPast {
                            Text("暂无同步")
                        } else {
                            Text(status.lastUpdateTime, style: .time)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.trailing)
                }

                Divider().overlay(Color.gray.opacity(0.3))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "fuelpump.fill")
                            .foregroundStyle(mainColor)
                        Text("当前油量")
                            .foregroundStyle(.gray)
                    }
                    .font(.caption)
                    Text("\(status.fuelLevel)%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "flag.checkered")
                            .foregroundStyle(mainColor)
                        Text("小计里程")
                            .foregroundStyle(.gray)
                    }
                    .font(.caption)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", status.tripKm))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("km")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }

                Divider().overlay(Color.gray.opacity(0.3))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Image(systemName: "parkingsign.circle.fill")
                            .foregroundStyle(.orange)
                        Text("最后停车位置")
                            .foregroundStyle(.gray)
                    }
                    .font(.caption)

                    Text(status.address)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if status.parkedLat != 0 || status.parkedLon != 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                            Text(String(format: "%.5f, %.5f", status.parkedLat, status.parkedLon))
                        }
                        .font(.caption2)
                        .foregroundStyle(mainColor)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.1).ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
