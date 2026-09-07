//
//  PTBLELogger.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 12/8/2026.
//

import Foundation
import PooTools

// English: A value event keeps logger observers independent from the mutable logger instance.
// Español: Un evento de valor mantiene a los observadores independientes de la instancia mutable del registrador.
// 中文：值类型事件让日志观察者不依赖可变的日志实例。
nonisolated public struct PTOBDLogEntry: Sendable {
    public let timestamp: Date
    public let monotonicNanoseconds: UInt64
    public let message: String

    public init(
        timestamp: Date = Date(),
        monotonicNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds,
        message: String
    ) {
        self.timestamp = timestamp
        self.monotonicNanoseconds = monotonicNanoseconds
        self.message = message
    }
}

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

    // English: Token observers let passive protocol capture coexist with the legacy UI callback.
    // Español: Los observadores con token permiten que la captura pasiva coexista con el callback heredado de UI.
    // 中文：带 Token 的观察者让被动协议采集可以与旧 UI 回调共存。
    private let observerLock = NSLock()
    private var observers: [UUID: @Sendable (PTOBDLogEntry) -> Void] = [:]
    
    // 独占的后台 I/O 队列，保障主线程 UI 绝对流畅
    private let ioQueue = DispatchQueue(label: "com.ptools.MotoLogIOQueue.\(UUID().uuidString)", qos: .utility)
    
    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()
    
    // 允许外部自由实例化，实现日志完全隔离
    public init() {}

    // English: Add a non-invasive observer; it never changes transport behavior or log ownership.
    // Español: Añade un observador no invasivo; nunca cambia el transporte ni la propiedad del registro.
    // 中文：添加非侵入式观察者，不改变传输行为和日志所有权。
    @discardableResult
    public func addObserver(_ observer: @escaping @Sendable (PTOBDLogEntry) -> Void) -> UUID {
        let token = UUID()
        observerLock.lock()
        observers[token] = observer
        observerLock.unlock()
        return token
    }

    // English: Remove one observer without affecting the legacy callback.
    // Español: Elimina un observador sin afectar al callback heredado.
    // 中文：移除单个观察者，不影响旧回调。
    public func removeObserver(_ token: UUID) {
        observerLock.lock()
        observers.removeValue(forKey: token)
        observerLock.unlock()
    }
    
    // MARK: - 📝 日志生命周期控制
    
    /// 开启文件日志记录 (支持自定义前缀和标题)
    /// - Parameters:
    ///   - prefix: 文件名前缀，例如 "MotoHexLog" 或 "OBDTraceLog"
    ///   - headerTitle: 写入文件头部的说明文字
    public func startFileLogging(prefix: String = "MotoOBDLog", headerTitle: String = "PEUGEOT XP400GT TRACE LOG") {
        // English: Serialize open, append, and close so a disconnect cannot race a queued write.
        // Español: Serializa abrir, añadir y cerrar para que una desconexión no compita con una escritura pendiente.
        // 中文：串行化打开、追加和关闭，避免断开时与排队写入发生竞争。
        ioQueue.sync {
            guard logFileHandle == nil else { return }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "\(prefix)_\(formatter.string(from: Date())).txt"

            guard let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let fileURL = docsDir.appendingPathComponent(fileName)
            currentLogFileURL = fileURL

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
    }
    
    /// 停止日志记录并封装文件
    public func stopFileLogging() {
        ioQueue.sync {
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
    }
    
    // MARK: - 🖋 核心写入方法
    
    public func ptLog(_ message: String) {
        let now = Date()
        observerLock.lock()
        let timeString = dateFormatter.string(from: now)
        let currentObservers = Array(observers.values)
        observerLock.unlock()
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

        let entry = PTOBDLogEntry(
            timestamp: now,
            monotonicNanoseconds: DispatchTime.now().uptimeNanoseconds,
            message: message
        )
        DispatchQueue.main.async {
            currentObservers.forEach { $0(entry) }
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
