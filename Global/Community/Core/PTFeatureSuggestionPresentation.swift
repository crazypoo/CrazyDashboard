//
//  PTFeatureSuggestionPresentation.swift
//  CrazyDashboard
//

import Foundation

@MainActor
enum PTFeatureSuggestionPresentation {
    static func status(_ state: PTFeatureSuggestionState) -> String {
        switch state {
        case .reviewing:
            return PTFeedbackPresentation.text("feedback_status_reviewing", fallback: "评估中")
        case .published:
            return PTFeedbackPresentation.text("feedback_status_published", fallback: "已采纳")
        case .planned:
            return PTFeedbackPresentation.text("feedback_status_planned", fallback: "处理中")
        case .resolved:
            return PTFeedbackPresentation.text("feedback_status_resolved", fallback: "已解决")
        case .declined:
            return PTFeedbackPresentation.text("feedback_status_declined", fallback: "暂未采纳")
        }
    }
}
