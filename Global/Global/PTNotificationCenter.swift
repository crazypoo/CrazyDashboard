//
//  PTNotificationCenter.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 24/7/2026.
//

import UIKit
import PooTools

class PTNotificationCenter: NSObject {
    static func pushCenter(title: String, body: String,trigger:UNNotificationTrigger? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        content.interruptionLevel = .timeSensitive

        // 生成唯一请求 ID
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        // 将请求加入系统通知中心
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                PTNSLogConsole("❌ [消息推送] 发送失败: \(error.localizedDescription)")
            } else {
                PTNSLogConsole("🚀 [消息推送] 消息已交给 iOS 系统，即将通过 ANCS 弹窗推送到车机！")
            }
        }
    }
}
