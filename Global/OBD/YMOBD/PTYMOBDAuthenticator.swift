// EN: Own YMOBD challenge generation and response verification only.
// ES: Gestiona únicamente la generación del desafío YMOBD y la verificación de respuestas.
// 中文：只负责 YMOBD challenge 生成与响应校验。

import Foundation

public struct PTYMOBDAuthResult: Equatable, Sendable {
    public let command: String
    public let challenge: UInt32?

    public init(command: String, challenge: UInt32?) {
        self.command = command
        self.challenge = challenge
    }
}

public final class PTYMOBDAuthenticator {
    public private(set) var isOfficialYMOBD = false

    public init() {}

    public func reset() {
        isOfficialYMOBD = false
    }

    public func makeAuthCommand(versionInfo: PTYMOBDVersionInfo) -> PTYMOBDAuthResult? {
        guard versionInfo.isYMOBD else { return nil }

        if !versionInfo.crypt.isEmpty {
            let setCryptCommand = YmobdCrypt.setCryptCommand(cryptFromVersion: versionInfo.crypt)
            if !setCryptCommand.isEmpty {
                return PTYMOBDAuthResult(
                    command: setCryptCommand.replacingOccurrences(of: "\r", with: ""),
                    challenge: nil
                )
            }
        }

        let challenge = YmobdCrypt.newChallenge()
        return PTYMOBDAuthResult(
            command: YmobdCrypt.challengeCommand(challenge: challenge).replacingOccurrences(of: "\r", with: ""),
            challenge: UInt32(bitPattern: challenge)
        )
    }

    public func verify(command: String, response: String, challenge: UInt32?) -> Bool {
        let normalizedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let compactResponse = response
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        let verified: Bool
        if normalizedCommand.hasPrefix("AT+SETCRYPT") {
            verified = !compactResponse.isEmpty
                && !compactResponse.contains("ERROR")
                && !compactResponse.contains("NODATA")
                && !compactResponse.contains("?")
                && !compactResponse.contains("UNABLETOCONNECT")
        } else if normalizedCommand.hasPrefix("AT+CRYPT") {
            guard let challenge else {
                isOfficialYMOBD = false
                return false
            }

            let expected = YmobdCrypt.hex8(
                value: YmobdCrypt.crypt32(input: Int32(bitPattern: challenge))
            )
            let responseWithoutEcho = response.replacingOccurrences(
                of: command,
                with: "",
                options: .caseInsensitive
            )
            verified = firstEightDigitHexToken(from: responseWithoutEcho) == expected
        } else {
            verified = false
        }

        isOfficialYMOBD = verified
        return verified
    }

    private func firstEightDigitHexToken(from response: String) -> String? {
        guard let expression = try? NSRegularExpression(
            pattern: "(?i)(?<![0-9a-f])[0-9a-f]{8}(?![0-9a-f])"
        ) else { return nil }

        let range = NSRange(response.startIndex..<response.endIndex, in: response)
        guard let match = expression.firstMatch(in: response, range: range),
              let tokenRange = Range(match.range, in: response) else {
            return nil
        }
        return String(response[tokenRange]).uppercased()
    }
}
