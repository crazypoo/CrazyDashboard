//
//  PTFeedbackRedactor.swift
//  CrazyDashboard
//

import Foundation

nonisolated public enum PTFeedbackRedactor {
    private struct Rule: Sendable {
        let pattern: String
        let replacement: String
    }

    private static let rules: [Rule] = [
        .init(
            pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            replacement: "[REDACTED_EMAIL]"
        ),
        .init(
            pattern: #"(?i)\b(?:[0-9A-F]{2}[:-]){5}[0-9A-F]{2}\b"#,
            replacement: "[REDACTED_MAC]"
        ),
        .init(
            pattern: #"(?i)\b[0-9A-F]{8}-[0-9A-F]{4}-[1-5][0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}\b"#,
            replacement: "[REDACTED_UUID]"
        ),
        .init(
            pattern: #"\b(?=[A-HJ-NPR-Z0-9]{17}\b)(?=.*[0-9])(?=.*[A-HJ-NPR-Z])[A-HJ-NPR-Z0-9]{17}\b"#,
            replacement: "[REDACTED_VIN]"
        ),
        .init(
            pattern: #"(?<!\d)[+-]?(?:90(?:\.0+)?|[0-8]?\d(?:\.\d+)?)[,\s]+[+-]?(?:180(?:\.0+)?|1[0-7]\d(?:\.\d+)?|\d?\d(?:\.\d+)?)(?!\d)"#,
            replacement: "[REDACTED_COORDINATE]"
        ),
        .init(
            pattern: #"\b(?:\+?\d[\d\s().-]{7,}\d)\b"#,
            replacement: "[REDACTED_PHONE]"
        )
    ]

    public static func redact(_ input: String) -> String {
        var output = input

        for rule in rules {
            guard let regex = try? NSRegularExpression(
                pattern: rule.pattern
            ) else {
                continue
            }

            let range = NSRange(
                output.startIndex..<output.endIndex,
                in: output
            )

            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: rule.replacement
            )
        }

        return output
    }
}
