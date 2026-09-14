//
//  PTOBDCompatibilityFacade.swift
//  PTSpeed
//
//  EN: Provides an opt-in migration surface while preserving every legacy caller.
//  ES: Proporciona una superficie de migración opcional y conserva todos los llamadores heredados.
//  中文：提供可选的迁移入口，同时保留所有旧调用方。
//

import Foundation

@MainActor
public final class PTOBDCompatibilityFacade {
    public static let shared = PTOBDCompatibilityFacade()

    private var session: PTELM327Session?

    private init() {}

    public func attach(session: PTELM327Session) async {
        self.session = session
        await PTOBDCompatibilityGateway.shared.attach(session: session)
    }

    public func detach() async {
        session = nil
        await PTOBDCompatibilityGateway.shared.detachSession()
    }

    public func execute(
        _ rawCommand: String,
        requiresPause: Bool = true,
        context: PTOBDCommandExecutionContext = .ordinary,
        leaseToken: PTOBDBusLeaseToken? = nil
    ) async throws -> String {
        guard let session else {
            return try await PTOBDCommandGateway.shared.execute(
                rawCommand,
                requiresPause: requiresPause,
                context: context,
                leaseToken: leaseToken
            )
        }

        let classification = PTOBDCommandClassifierV2.classify(rawCommand)
        try validateSyntax(for: classification)
        try authorize(classification: classification, context: context)

        let operation: @Sendable () async throws -> String = {
            let response = try await session.execute(
                classification.normalizedCommand,
                classification: classification
            )
            return response.raw
        }

        if let leaseToken {
            guard await PTOBDBusLease.shared.isCurrent(leaseToken) else {
                throw PTOBDCommandGatewayError.leaseUnavailable
            }
            return try await operation()
        }

        return try await PTOBDBusCoordinator.shared.withBus(
            purpose: PTOBDCommandClassifierV2.busPurpose(for: classification),
            operation: operation
        )
    }
}

private extension PTOBDCompatibilityFacade {
    func authorize(
        classification: PTOBDCommandClassificationV2,
        context: PTOBDCommandExecutionContext
    ) throws {
        switch context {
        case .ordinary:
            guard [.telemetryRead, .diagnosticRead].contains(classification.kind),
                  PTOBDCommandClassifier.isOrdinaryReadAllowed(classification.normalizedCommand) else {
                throw PTOBDCommandGatewayError.denied(.unknown)
            }
        case .recovery:
            guard classification.kind == .elmConfiguration,
                  PTOBDCommandClassifier.isSafeRecoveryCommand(classification.normalizedCommand) else {
                throw PTOBDCommandGatewayError.denied(.stateChanging)
            }
        case let .developer(operation):
            guard PTDeveloperSafetyGate.shared.authorize(operation) else {
                throw PTOBDCommandGatewayError.denied(.unknown)
            }
        }
    }

    func validateSyntax(
        for classification: PTOBDCommandClassificationV2
    ) throws {
        guard !classification.normalizedCommand.isEmpty,
              classification.normalizedCommand.count <= PTELM327Session.maximumCommandLength else {
            throw PTOBDCommandGatewayError.invalidCommand
        }

        guard classification.normalizedCommand.hasPrefix("AT")
            || (classification.normalizedCommand.count.isMultiple(of: 2)
                && classification.normalizedCommand.allSatisfy({ $0.isHexDigit })) else {
            throw PTOBDCommandGatewayError.invalidCommand
        }
    }
}
