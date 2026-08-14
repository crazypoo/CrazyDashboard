//
//  PTBLELogger.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation
import PooTools

// MARK: - 🌟 升级版：支持多实例隔离的底层日志追踪引擎
public class PTOBDLogger {
    
    // 兼容旧代码的默认全局单例
    public static let shared = PTOBDLogger()
    
    // 💡 推荐：专门用于摩托车蓝牙通信的独立日志实例
    public static let moto = PTOBDLogger()
    
    // 💡 推荐：专门用于 OBD/UDS 诊断与抓包的独立日志实例
    public static let obd = PTOBDLogger()
    
    private var logFileHandle: FileHandle?
    public private(set) var currentLogFileURL: URL?
    public private(set) var logHistory: [String] = []
    
    // UI 监听的全局回调
    public var onLogUpdated: ((String) -> Void)?
    
    // 独占的后台 I/O 队列，保障主线程 UI 绝对流畅
    private let ioQueue = DispatchQueue(label: "com.ptools.MotoLogIOQueue.\(UUID().uuidString)", qos: .utility)
    
    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    // 允许外部自由实例化，实现日志完全隔离
    public init() {}
    
    // MARK: - 📝 日志生命周期控制
    
    /// 开启文件日志记录 (支持自定义前缀和标题)
    /// - Parameters:
    ///   - prefix: 文件名前缀，例如 "MotoHexLog" 或 "OBDTraceLog"
    ///   - headerTitle: 写入文件头部的说明文字
    public func startFileLogging(prefix: String = "MotoOBDLog", headerTitle: String = "PEUGEOT XP400GT TRACE LOG") {
        // 防止重复开启
        guard logFileHandle == nil else { return }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let fileName = "\(prefix)_\(formatter.string(from: Date())).txt"
        
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docsDir.appendingPathComponent(fileName)
        currentLogFileURL = fileURL
        
        // 在沙盒中创建空文件
        FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil)
        
        do {
            logFileHandle = try FileHandle(forWritingTo: fileURL)
            let header = "=== \(headerTitle) ===\n=== SESSION START: \(Date()) ===\n\n"
            if let data = header.data(using: .utf8) {
                try logFileHandle?.seekToEnd()
                try logFileHandle?.write(contentsOf: data)
            }
            PTNSLogConsole("📝 [日志系统 - \(prefix)] 已开启独立文件写入: \(fileName)")
        } catch {
            PTNSLogConsole("❌ [日志系统 - \(prefix)] 文件创建失败: \(error)")
        }
    }
    
    /// 停止日志记录并封装文件
    public func stopFileLogging() {
        guard let handle = logFileHandle else { return }
        let footer = "\n=== SESSION END: \(Date()) ===\n"
        if let data = footer.data(using: .utf8) {
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        }
        try? handle.close()
        logFileHandle = nil
        PTNSLogConsole("💾 [日志系统] 会话结束，独立日志文件已安全封装。")
    }
    
    // MARK: - 🖋 核心写入方法
    
    public func ptLog(_ message: String) {
        let timeString = dateFormatter.string(from: Date())
        let formattedLog = "[\(timeString)] \(message)"
        
        // 控制台打印
//        PTNSLogConsole(formattedLog)
        
        // 异步磁盘写入
        ioQueue.async { [weak self] in
            guard let self = self, let handle = self.logFileHandle else { return }
            if let data = (formattedLog + "\n").data(using: .utf8) {
                _ = try? handle.seekToEnd()
                _ = try? handle.write(contentsOf: data)
            }
        }
        
        // 主线程派发 UI 更新
        DispatchQueue.main.async {
            self.logHistory.append(formattedLog)
            if self.logHistory.count > 1000 { self.logHistory.removeFirst() }
            self.onLogUpdated?(formattedLog)
        }
    }
    
    // MARK: - 📂 文件检索系统
    
    public func fetchAllLogFiles(prefix: String = "Moto") -> [URL] {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: [.creationDateKey])
            let logFiles = files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "txt" }
            return logFiles.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
        } catch {
            return []
        }
    }
}
