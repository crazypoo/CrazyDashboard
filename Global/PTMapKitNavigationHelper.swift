//
//  PTMapKitNavigationHelper.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import MapKit
import CoreLocation
import PooTools

// MARK: - 1. 字符串扩展：摩托车仪表盘 ASCII 兼容处理
extension String {
    /// 将包含中文的字符串转换为无声调的拼音，并自动优化常用导航词汇为英文
    func toMotorcycleCompatiblePinyin() -> String {
        let mutableString = NSMutableString(string: self)
        
        // 1. 汉字转带声调拉丁字母
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        // 2. 剥离声调
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        
        var result = String(mutableString)
        
        // 3. 常用导航术语与路名的体验优化字典
        let optimizeDictionary: [String: String] = [
            "dao da": "Arrive",
            "zhong dian": "Destination",
            "zhi xing": "Straight",
            "ji xu": "Continue",
            "zuo zhuan": "Turn Left",
            "xiang zuo": "Turn Left",
            "you zhuan": "Turn Right",
            "xiang you": "Turn Right",
            "diao tou": "U-Turn",
            "kao zuo": "Keep Left",
            "kao you": "Keep Right",
            "da dao": "Blvd",
            "lu": "Rd",
            "jie": "St",
            "qiao": "Bridge"
        ]
        
        // 4. 执行关键词英文润色
        for (pinyin, english) in optimizeDictionary {
            result = result.replacingOccurrences(of: pinyin, with: english, options: .caseInsensitive)
        }
        
        return result
    }
}
