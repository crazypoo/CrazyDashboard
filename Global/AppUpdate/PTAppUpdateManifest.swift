//
//  PTAppUpdateManifest.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 17/9/2026.
//

import Foundation

struct PTAppUpdateManifest: Decodable, Sendable {

    struct App: Decodable, Sendable {
        let name: String
        let bundleId: String
    }

    struct BetaGroup: Decodable, Sendable {
        let name: String
        let isInternal: Bool
        let state: String
    }

    struct Latest: Decodable, Sendable {
        let version: String
        let build: String
        let buildId: String
        let uploadedAt: Date
        let expiresAt: Date
    }

    struct TestFlight: Decodable, Sendable {
        let url: String?
    }

    struct Policy: Decodable, Sendable {

        struct MinimumSupported: Decodable, Sendable {
            let version: String
            let build: String
        }

        let enabled: Bool
        let minimumSupported: MinimumSupported?
    }

    let schemaVersion: Int
    let generatedAt: Date

    let app: App
    let betaGroup: BetaGroup
    let latest: Latest
    let testFlight: TestFlight

    let releaseNotes: [String: String]

    let policy: Policy
}
