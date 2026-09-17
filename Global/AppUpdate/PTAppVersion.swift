//
//  PTAppVersion.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 17/9/2026.
//

import Foundation

struct PTAppVersion: Sendable, Equatable, Comparable {

    let version: String
    let build: String

    static var current: PTAppVersion {

        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"

        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "0"

        return .init(
            version: version,
            build: build
        )
    }

    static func < (lhs: PTAppVersion, rhs: PTAppVersion) -> Bool {
        let versionResult = lhs.version.compare(
            rhs.version,
            options: .numeric
        )

        if versionResult != .orderedSame {
            return versionResult == .orderedAscending
        }

        return lhs.build.compare(
            rhs.build,
            options: .numeric
        ) == .orderedAscending
    }
}
