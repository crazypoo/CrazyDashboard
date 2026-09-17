//
//  PTAppUpdateManager.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 17/9/2026.
//

import Foundation

@MainActor
final class PTAppUpdateManager {

    static let shared = PTAppUpdateManager()

    private let checkInterval: TimeInterval = 30 * 60
    private let requiredManifestMaxAge: TimeInterval = 24 * 60 * 60

    private var lastCheckDate: Date?

    private let manifestURL = URL(
        string:
        "https://crazypoo.github.io/CrazyDashboard/testflight/version.json"
    )!

    private init() {}

    func checkIfNeeded(
        force: Bool = false
    ) async -> PTAppUpdateResult {

        if !force,
           let lastCheckDate,
           Date().timeIntervalSince(lastCheckDate) < checkInterval {
            return .latest
        }

        lastCheckDate = Date()

        do {

            let manifest = try await requestManifest()

            guard manifest.policy.enabled else {
                return .latest
            }

            guard manifest.app.bundleId == Bundle.main.bundleIdentifier else {
                return .unavailable
            }

            guard manifest.latest.expiresAt > Date() else {
                return .unavailable
            }

            let current = PTAppVersion.current

            let latest = PTAppVersion(
                version: manifest.latest.version,
                build: manifest.latest.build
            )

            guard current < latest else {
                return .latest
            }

            if let minimum = manifest.policy.minimumSupported {

                let minimumVersion = PTAppVersion(
                    version: minimum.version,
                    build: minimum.build
                )

                // 防止错误配置 minimum > latest
                if minimumVersion <= latest,
                   current < minimumVersion {

                    let age = Date().timeIntervalSince(
                        manifest.generatedAt
                    )

                    if age <= requiredManifestMaxAge {
                        return .required(
                            manifest: manifest
                        )
                    }
                }
            }

            return .optional(
                manifest: manifest
            )

        } catch {
            return .unavailable
        }
    }

    private func requestManifest() async throws -> PTAppUpdateManifest {

        var request = URLRequest(
            url: manifestURL
        )

        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(
            for: request
        )

        guard
            let httpResponse = response as? HTTPURLResponse,
            200..<300 ~= httpResponse.statusCode
        else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()

        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(
            PTAppUpdateManifest.self,
            from: data
        )
    }
}
