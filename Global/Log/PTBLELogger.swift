//
//  PTBLELogger.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation
import PooTools

// MARK: - 🌟 全局底层统一日志追踪引擎
public class PTOBDLogger {
    public static let shared = PTOBDLogger()
    
    private var logFileHandle: FileHandle?
    public private(set) var currentLogFileURL: URL?
    public private(set) var logHistory: [String] = []
    
    // UI 监听的全局回调
    public var onLogUpdated: ((String) -> Void)?
    
    // 独占的后台 I/O 队列，保障主线程 UI 绝对流畅
    private let ioQueue = DispatchQueue(label: "com.ptools.MotoLogIOQueue", qos: .utility)
    
    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    private init() {} // 单例私有化
    
    // MARK: - 📝 日志生命周期控制
    
    /// 开启文件日志记录 (支持自定义前缀和标题)
    /// - Parameters:
    ///   - prefix: 文件名前缀，例如 "MotoOBDLog" 或 "MotoHexLog"
    ///   - headerTitle: 写入文件头部的说明文字
    public func startFileLogging(prefix: String = "MotoOBDLog", headerTitle: String = "PEUGEOT XP400GT OBD TRACE LOG") {
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
            PTNSLogConsole("📝 [日志系统] 已开启全链路底层写入: \(fileName)")
        } catch {
            PTNSLogConsole("❌ [日志系统] 文件创建失败: \(error)")
        }
    }
    
    /// 停止日志记录并封装文件
    public func stopFileLogging() {
        guard logFileHandle != nil else { return }
        let footer = "\n=== SESSION END: \(Date()) ===\n"
        if let data = footer.data(using: .utf8) {
            _ = try? logFileHandle?.seekToEnd()
            _ = try? logFileHandle?.write(contentsOf: data)
        }
        try? logFileHandle?.close()
        logFileHandle = nil
        PTNSLogConsole("💾 [日志系统] 会话结束，日志已安全封装。")
    }
    
    // MARK: - 🖋 核心写入方法
    
    public func ptLog(_ message: String) {
        let timeString = dateFormatter.string(from: Date())
        let formattedLog = "[\(timeString)] \(message)"
        
        // 控制台打印
        PTNSLogConsole(formattedLog)
        
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
            // 设定缓冲区大小 (如 1000 条)
            if self.logHistory.count > 1000 { self.logHistory.removeFirst() }
            self.onLogUpdated?(formattedLog)
        }
    }
    
    // MARK: - 📂 文件检索系统
    
    /// 获取沙盒中所有的日志文件，供 UI 导出使用
    /// - Parameter prefix: 检索的文件前缀，例如 "Moto" 可以搜出所有的日志
    public func fetchAllLogFiles(prefix: String = "Moto") -> [URL] {
        guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: [.creationDateKey])
            // 过滤出指定前缀并以 .txt 结尾的文件
            let logFiles = files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "txt" }
            // 按时间倒序排列 (最新的在最前)
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
