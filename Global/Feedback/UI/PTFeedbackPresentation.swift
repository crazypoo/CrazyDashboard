//
//  PTFeedbackPresentation.swift
//  CrazyDashboard
//

import Foundation

@MainActor
enum PTFeedbackPresentation {
    static func text(
        _ key: String,
        fallback: String
    ) -> String {
        let translated = PTDashboardConfig.languageFunc(
            text: key
        )

        return translated == key
            ? fallback
            : translated
    }

    static func categoryTitle(
        _ value: PTFeedbackCategory
    ) -> String {
        switch value {
        case .bug:
            return text("feedback_category_bug", fallback: "Bug")
        case .suggestion:
            return text("feedback_category_suggestion", fallback: "功能建议")
        case .usability:
            return text("feedback_category_usability", fallback: "使用体验")
        case .localization:
            return text("feedback_category_localization", fallback: "语言/翻译")
        case .compatibility:
            return text("feedback_category_compatibility", fallback: "兼容性")
        case .protocolResearch:
            return text("feedback_category_protocol", fallback: "协议研究")
        case .other:
            return text("feedback_category_other", fallback: "其他")
        }
    }

    static func moduleTitle(
        _ value: PTFeedbackModule
    ) -> String {
        switch value {
        case .app: return "App"
        case .xp400Dashboard: return "XP400 Dashboard"
        case .obd: return "OBD"
        case .ymobd: return "YMOBD"
        case .navigation: return text("feedback_module_navigation", fallback: "导航")
        case .carPlay: return "CarPlay"
        case .watch: return "Watch"
        case .widget: return "Widget"
        case .music: return text("feedback_module_music", fallback: "音乐")
        case .ride: return text("feedback_module_ride", fallback: "骑行")
        case .mock: return "Mock"
        case .cloud: return "CloudKit"
        case .protocolResearch: return text("feedback_category_protocol", fallback: "协议研究")
        case .other: return text("feedback_category_other", fallback: "其他")
        }
    }

    static func statusTitle(
        _ status: PTFeedbackStatus
    ) -> String {
        switch status {
        case .submitted:
            return text("feedback_status_submitted", fallback: "已提交")
        case .accepted:
            return text("feedback_status_accepted", fallback: "已收到")
        case .grouped:
            return text("feedback_status_grouped", fallback: "已合并分析")
        case .reviewing:
            return text("feedback_status_reviewing", fallback: "评估中")
        case .published:
            return text("feedback_status_published", fallback: "已采纳")
        case .planned:
            return text("feedback_status_planned", fallback: "处理中")
        case .resolved:
            return text("feedback_status_resolved", fallback: "已解决")
        case .declined:
            return text("feedback_status_declined", fallback: "暂未采纳")
        case .duplicate:
            return text("feedback_status_duplicate", fallback: "已合并到已有问题")
        case .rejected:
            return text("feedback_status_rejected", fallback: "无法处理")
        }
    }
}
