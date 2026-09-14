//
//  PTELM327VendorExtension.swift
//  PTSpeed
//
//  EN: Defines optional vendor behavior on top of one ELM327 session.
//  ES: Define el comportamiento opcional del proveedor sobre una sola sesión ELM327.
//  中文：定义建立在同一 ELM327 会话之上的可选厂商扩展行为。
//

import Foundation

@MainActor
public protocol PTELM327VendorExtension: AnyObject {
    var identifier: String { get }

    func probe(session: PTELM327Session) async throws -> Bool
}

public actor PTELM327VendorExtensionRegistry {
    public static let shared = PTELM327VendorExtensionRegistry()

    private var registered: [String: any PTELM327VendorExtension] = [:]
    private var active: Set<String> = []

    public init() {}

    public func register(_ extension: any PTELM327VendorExtension) async {
        let identifier = await `extension`.identifier
        registered[identifier] = `extension`
    }

    public func unregister(identifier: String) {
        registered.removeValue(forKey: identifier)
        active.remove(identifier)
    }

    public func probeAll(session: PTELM327Session) async -> [String] {
        let candidates = Array(registered.values)
        var activated: [String] = []
        for candidate in candidates {
            let identifier = await candidate.identifier
            do {
                if try await candidate.probe(session: session) {
                    activated.append(identifier)
                    active.insert(identifier)
                }
            } catch {
                active.remove(identifier)
            }
        }
        return activated.sorted()
    }

    public func activeIdentifiers() -> [String] {
        active.sorted()
    }

    public func reset() {
        active.removeAll(keepingCapacity: false)
    }
}
