//
//  PTELM327Parser.swift
//  PTSpeed
//
//  EN: Parses ELM327 prompt-terminated responses without owning a transport.
//  ES: Analiza respuestas ELM327 terminadas por prompt sin poseer el transporte.
//  中文：解析以 prompt 结束的 ELM327 响应，但不拥有传输层。
//

import Foundation

nonisolated public enum PTELM327ResponseStatus: String, Codable, Equatable, Sendable {
    case positive
    case noData
    case unableToConnect
    case stopped
    case searching
    case error
}

nonisolated public struct PTELM327Response: Codable, Equatable, Sendable {
    public let raw: String
    public let lines: [String]
    public let payloadLines: [String]
    public let status: PTELM327ResponseStatus
    public let isPromptTerminated: Bool

    public init(
        raw: String,
        lines: [String],
        payloadLines: [String],
        status: PTELM327ResponseStatus,
        isPromptTerminated: Bool
    ) {
        self.raw = raw
        self.lines = lines
        self.payloadLines = payloadLines
        self.status = status
        self.isPromptTerminated = isPromptTerminated
    }

    public var isUsable: Bool {
        status == .positive && !payloadLines.isEmpty
    }

    public var compactPayload: String {
        payloadLines.joined(separator: "\n")
    }
}

nonisolated public struct PTELM327Parser: Sendable {
    private var buffer = ""

    public init() {}

    public mutating func append(_ data: Data) -> [PTELM327Response] {
        guard let chunk = String(data: data, encoding: .ascii), !chunk.isEmpty else {
            return []
        }

        buffer.append(chunk)
        var responses: [PTELM327Response] = []

        while let prompt = buffer.firstIndex(of: ">") {
            let raw = String(buffer[..<prompt])
            let next = buffer.index(after: prompt)
            buffer = next < buffer.endIndex ? String(buffer[next...]) : ""
            responses.append(Self.parse(raw: raw, command: nil, promptTerminated: true))
        }

        return responses
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
    }

    public static func parse(
        raw: String,
        command: String? = nil,
        promptTerminated: Bool = false
    ) -> PTELM327Response {
        let normalizedCommand = command.map(normalize)
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != ">" }

        let payloadLines = lines.filter { line in
            guard let normalizedCommand else { return true }
            return normalize(line) != normalizedCommand
        }
        let compact = normalize(raw)
        let status: PTELM327ResponseStatus
        if compact.contains("UNABLETOCONNECT") {
            status = .unableToConnect
        } else if compact.contains("NODATA") {
            status = .noData
        } else if compact.contains("STOPPED") {
            status = .stopped
        } else if compact.contains("SEARCHING") {
            status = .searching
        } else if compact.contains("ERROR") || compact == "?" || compact.hasSuffix("?") {
            status = .error
        } else {
            status = .positive
        }

        return PTELM327Response(
            raw: raw,
            lines: lines,
            payloadLines: payloadLines,
            status: status,
            isPromptTerminated: promptTerminated
        )
    }

    public static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter { !$0.isWhitespace && $0 != "\r" && $0 != "\n" }
    }
}
