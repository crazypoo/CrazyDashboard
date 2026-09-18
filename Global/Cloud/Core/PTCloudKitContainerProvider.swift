//
//  PTCloudKitContainerProvider.swift
//  CrazyDashboard
//

@preconcurrency import CloudKit
import Foundation

/// Keep CKContainer / CKDatabase objects inside actors that use this provider.
/// Do not expose CloudKit reference types across concurrency boundaries.
nonisolated public enum PTCloudKitContainerProvider {
    public static func makeContainer(
        identifier: String
    ) -> CKContainer {
        CKContainer(identifier: identifier)
    }
}
