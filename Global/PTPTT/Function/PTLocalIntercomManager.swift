//
//  PTLocalIntercomManager.swift
//  PTSpeed
//
//  Created by 邓杰豪 on 30/7/2026.
//

import Foundation
import MultipeerConnectivity
import AVFoundation
import PooTools

public let PTIntercomGlobalStatusChanged = NSNotification.Name("PTIntercomGlobalStatusChanged")
public let PTPeerLocationDidUpdateNotification = NSNotification.Name("PTPeerLocationDidUpdateNotification")
public let PTPeerDidLeaveNetworkNotification = NSNotification.Name("PTPeerDidLeaveNetworkNotification")
public let PTPeerAvatarDidUpdateNotification = NSNotification.Name("PTPeerAvatarDidUpdateNotification")

public enum PTNetworkSignalLevel {
    case strong // 满格绿信号 (< 50ms)
    case normal // 两格黄信号 (50 ~ 150ms)
    case weak   // 一格红信号 (> 150ms)
}

public struct PTPeerLocation: Codable {
    public let lat: Double     // 纬度
    public let lon: Double     // 经度
    public let course: Double  // 车头朝向 (用于地图上旋转图标)
    public let speed: Double   // 车速
    public let originalSender: String // 源头发件人的 UUID
    public let messageID: String
    public var ttl: Int = 10
    public init(lat: Double, lon: Double, course: Double, speed: Double, originalSender: String, ttl: Int = 10) {
        self.lat = lat
        self.lon = lon
        self.course = course
        self.speed = speed
        self.originalSender = originalSender
        self.ttl = ttl
        // 使用 UUID 结合时间戳作为绝对唯一的 ID
        self.messageID = "\(originalSender)_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(6))"
    }
}

// MARK: - 状态回调协议，用于通知 UI 更新
public protocol PTLocalIntercomDelegate: AnyObject {
    func intercomManager(_ manager: PTLocalIntercomManager, didChangeStatus status: String)
    func intercomManager(_ manager: PTLocalIntercomManager, didUpdatePeers count: Int)
    func intercomManager(_ manager: PTLocalIntercomManager, didUpdatePeerList peers: [MCPeerID])
    func intercomManager(_ manager: PTLocalIntercomManager, speakingPeersChanged speakingPeers: [MCPeerID])
    func intercomManager(_ manager: PTLocalIntercomManager, localUserIsSpeaking: Bool)
    func intercomManager(_ manager: PTLocalIntercomManager, didUpdateNetworkStatusFor peer: MCPeerID, latency: Int, signal: PTNetworkSignalLevel)
}

@objcMembers
public class PTLocalIntercomManager: NSObject {
    
    public static let shared = PTLocalIntercomManager()
    public weak var delegate: PTLocalIntercomDelegate?
    
    private let audioQueue = DispatchQueue(label: "com.ptools.audioQueue", qos: .userInitiated)
    // 多点连接组件
    private let serviceType = "pt-moto-voice"
    private var myPeerId: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    // 音频引擎组件
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private let commonFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
    public private(set) var isTalking: Bool = false {
        didSet { if oldValue != isTalking { globalStatusChangeSet() } }
    }
    
    public private(set) var isHandsFreeMode: Bool = false {
        didSet { if oldValue != isHandsFreeMode { globalStatusChangeSet() } }
    }
    public var voiceThreshold: Float = 0.009
    private var lastSpokenTime: Date = Date.distantPast
    private let voxHangTime: TimeInterval = 0.8
    
    public private(set) var isRunning: Bool = false {
        didSet { if oldValue != isRunning { globalStatusChangeSet() } }
    }
    
    public private(set) var currentStatusText: String = PTDashboardConfig.languageFunc(text: "ptt_ready_connect") {
        didSet { if oldValue != currentStatusText { globalStatusChangeSet() } }
    }
    private let intercomPowerStateKey = "PTIntercomPowerStateKey"
    
    public var micVolumeMultiplier: Float = 3.0
    
    private var lastReceivedAudio: [MCPeerID: Date] = [:]
    private var currentSpeakingPeers: Set<MCPeerID> = []
    private var speakingTimer: Timer?

    private var pingTimer: Timer?
    
    public private(set) var otherMemberTalking: Bool = false {
        didSet { if oldValue != otherMemberTalking { globalStatusChangeSet() } }
    }

    public private(set) var isLocalUserSpeaking: Bool = false {
        didSet {
            // 只有状态发生翻转时，才通知外部 UI
            if oldValue != isLocalUserSpeaking {
                DispatchQueue.main.async {
                    self.delegate?.intercomManager(self, localUserIsSpeaking: self.isLocalUserSpeaking)
                }
            }
        }
    }

    public private(set) var activePeers: [MCPeerID] = [] {
        didSet { if oldValue.count != activePeers.count { globalStatusChangeSet() } }
    }
    private var connectingPeers: Set<MCPeerID> = []
    
    public var connectedPeersCount: Int {
        return activePeers.count
    }

    private var hasConnectedPeers: Bool {
        !activePeers.isEmpty
    }

    private lazy var myUUID: String = {
        let key = "PT_Device_Unique_UUID"
        if let savedUUID = UserDefaults.standard.string(forKey: key) { return savedUUID }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: key)
        return newUUID
    }()
    
    public var customUserName: String {
        get { return UserDefaults.standard.string(forKey: "PT_CustomUserName") ?? UIDevice.current.name }
        set { UserDefaults.standard.set(newValue, forKey: "PT_CustomUserName") }
    }

    private let myAvatarFileName = "PT_MyCustomAvatar.jpg"
    
    private let appGroupID = "group.com.yd.PTSpeed.xp400"
    
    private var peerAvatars: [MCPeerID: UIImage] = [:]
    
    public func currentMyAvatar() -> UIImage {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // 如果沙盒异常，直接兜底返回 Assets 里的默认头像 (请确保 Assets 中存在 "default_user_avatar" 图片)
            return UIImage(named: "placeholder")!
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(myAvatarFileName)
        
        // 如果沙盒里有用户选过的相册图片，优先返回它
        if FileManager.default.fileExists(atPath: fileURL.path),
           let savedImage = UIImage(contentsOfFile: fileURL.path) {
            return savedImage
        }
        
        // 否则，返回 Assets 里的默认头像
        return UIImage(named: "placeholder")!
    }

    private var processedMessageIDs: [String: Date] = [:]
    
    private override init() {
        super.init()
        setupPeerID()
        setupMultipeer()
        
        audioQueue.async {
            self.setupAudioEngine(needsMic: false)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func sendMyAvatar(to peer: MCPeerID, avatarImage: UIImage) {
        guard let jpegData = avatarImage.jpegData(compressionQuality: 0.5) else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("my_avatar_\(myUUID).jpg")
        
        do {
            try jpegData.write(to: tempURL)
            // 发送资源文件，"AVATAR_IMAGE" 是我们约定的标识符
            session.sendResource(at: tempURL, withName: "AVATAR_IMAGE", toPeer: peer) { error in
                if let err = error {
                    PTNSLogConsole("❌ [头像同步] 发送给 \(peer.displayName) 失败: \(err.localizedDescription)")
                } else {
                    PTNSLogConsole("✅ [头像同步] 头像已成功发送给 \(peer.displayName)")
                }
            }
        } catch {
            PTNSLogConsole("❌ [头像同步] 临时文件写入失败: \(error)")
        }
    }
    
    public func updateAndBroadcastMyAvatar(_ image: UIImage) {
        // 第一步：持久化保存到本地沙盒
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = documentsDirectory.appendingPathComponent(myAvatarFileName)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
            PTNSLogConsole("✅ [头像持久化] 新头像已保存至本地")
        }
        
        // 第二步：立刻把新头像同步给当前局域网内的所有队友
        let peers = session.connectedPeers
        guard !peers.isEmpty else {
            PTNSLogConsole("ℹ️ [头像同步] 当前没有连接的队友，仅保存在本地。")
            return
        }
        
        for peer in peers {
            sendMyAvatar(to: peer, avatarImage: image)
        }
    }

    private func setupPeerID() {
        let peerIDKey = "PT_SavedMCPeerID"
        if let data = UserDefaults.standard.data(forKey: peerIDKey),
           let savedPeer = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            
            // 验证缓存的名字是否和当前设置的名字一致
            if savedPeer.displayName == customUserName {
                self.myPeerId = savedPeer
                PTNSLogConsole("✅ [组网] 成功读取固化身份: \(savedPeer.displayName)")
                return
            } else {
                PTNSLogConsole("🔄 [组网] 检测到昵称已更改，正在废弃旧身份...")
            }
        }
        
        // 创建新身份
        let newPeer = MCPeerID(displayName: customUserName)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: newPeer, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: peerIDKey)
        }
        self.myPeerId = newPeer
        PTNSLogConsole("🆕 [组网] 生成新身份: \(newPeer.displayName)")
    }

    public func updateUserName(newName: String) {
        guard newName != customUserName else { return }
        customUserName = newName
        
        let wasRunning = self.isRunning
        if wasRunning { stopOfflineIntercom() }
        
        setupPeerID() // 重新生成身份
        
        if wasRunning { startOfflineIntercom() }
    }

    private func startPingTimer() {
        stopPingTimer()
        // 每 2 秒钟对所有成员进行一次网络测速
        pingTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(sendPingToAll), userInfo: nil, repeats: true)
    }
    
    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    @objc private func sendPingToAll() {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }

        // 生成极小的时间戳文本数据
        let pingString = "PING:\(Date().timeIntervalSince1970)"
        guard let pingData = pingString.data(using: .utf8) else { return }
        
        // 发送给所有人 (.reliable 保证数据必达)
        do {
            try session.send(pingData, toPeers: peers, with: .reliable)
        } catch {
            PTNSLogConsole("❌ 心跳包发送失败: \(error.localizedDescription)")
        }
    }

    public func broadcastMyLocation(lat: Double, lon: Double, course: Double, speed: Double) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        
        let locData = PTPeerLocation(
            lat: lat,
            lon: lon,
            course: course,
            speed: speed,
            originalSender: self.myUUID,
            ttl: 10
        )

        if let jsonData = try? JSONEncoder().encode(locData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            
            // 加上 "LOC:" 前缀，打包发送
            let payloadString = "LOC:\(jsonString)"
            guard let payloadData = payloadString.data(using: .utf8) else { return }
            
            // 使用 .unreliable 发送，确保即使瞬间断网也不阻塞音频流
            try? session.send(payloadData, toPeers: peers, with: .unreliable)
        }
    }

    private func setupMultipeer() {
        session?.disconnect()
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        
        // 🌟 2. 每次都生成一个极其纯净、全新的 Session！
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: ["uuid": myUUID], serviceType: serviceType)
        advertiser.delegate = self
        
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self

    }
    
    public func startOfflineIntercom() {
        guard !isRunning else { return }

        // 新建组网会话前清掉上一次会话可能残留的成员状态。
        activePeers.removeAll()
        connectingPeers.removeAll()
        isRunning = true
        
        UserDefaults.standard.set(true, forKey: intercomPowerStateKey)
        
        setupMultipeer()
        
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        
        currentStatusText = PTDashboardConfig.languageFunc(text: "ptt_find_friend")
        updateStatusAndBroadcast(currentStatusText)
    }
    
    public func stopOfflineIntercom() {
        let wasRunning = isRunning
        isRunning = false
        
        UserDefaults.standard.set(false, forKey: intercomPowerStateKey)
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        activePeers.removeAll()
        connectingPeers.removeAll()
        
        // 如果开启了免提，重置它
        isHandsFreeMode = false
        isTalking = false
        isLocalUserSpeaking = false // 重置状态
        
        stopSpeakingDetector()
        stopPingTimer()
        Task { @MainActor in
            PTLiveActivityManager.shared.stopIntercomActivity()
        }

        guard wasRunning else { return }

        audioEngine.stop()
        audioQueue.async {
            self.setupAudioEngine(needsMic: false)
        }

        currentStatusText = PTDashboardConfig.languageFunc(text: "ptt_close")
        updateStatusAndBroadcast(currentStatusText)
    }
    
    private func startSpeakingDetector() {
        stopSpeakingDetector()
        speakingTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(checkSpeakingStatus), userInfo: nil, repeats: true)
    }
    
    private func stopSpeakingDetector() {
        speakingTimer?.invalidate()
        speakingTimer = nil
        lastReceivedAudio.removeAll()
        currentSpeakingPeers.removeAll()
    }
    
    @objc private func checkSpeakingStatus() {
        let now = Date()
        var newSpeaking: Set<MCPeerID> = []
        
        for (peer, lastTime) in lastReceivedAudio {
            if now.timeIntervalSince(lastTime) < 0.5 {
                newSpeaking.insert(peer)
            }
        }
        
        // 状态发生改变时，通知 UI
        if newSpeaking != currentSpeakingPeers {
            currentSpeakingPeers = newSpeaking
            let wasOtherMemberTalking = otherMemberTalking
            otherMemberTalking = !newSpeaking.isEmpty
            DispatchQueue.main.async {
                self.delegate?.intercomManager(self, speakingPeersChanged: Array(self.currentSpeakingPeers))
            }
            // 如果只是讲话者切换但仍有人讲话，属性值不会变化，仍需刷新 Live Activity。
            if wasOtherMemberTalking == otherMemberTalking {
                globalStatusChangeSet()
            }
        }
    }

    private func updateAudioSession(needsMic: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            if needsMic {
                let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetoothHFP, .mixWithOthers,.duckOthers]
                try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
            } else {
                let options: AVAudioSession.CategoryOptions = [.mixWithOthers]
                try session.setCategory(.playback, mode: .default, options: options)
            }
            try session.setActive(true)
        } catch {
            PTNSLogConsole("❌ [音频引擎] AudioSession 动态切换失败: \(error)")
        }
    }
    
    private func setupAudioEngine(needsMic: Bool) {
        audioEngine.stop() // 停掉旧的
        
        updateAudioSession(needsMic: needsMic)
        
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: commonFormat)
        
        if needsMic {
            _ = audioEngine.inputNode
        }
        
        restartEngineHard()
    }

    private func safeStartPlayerNode() {
        if !audioEngine.isRunning {
            restartEngineHard()
        }
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    private func restartEngineHard() {
        do {
            audioEngine.prepare()
            try audioEngine.start()
            PTNSLogConsole("🔄 [音频引擎] 成功从休克状态中硬重启！")
        } catch {
            PTNSLogConsole("❌ [音频引擎] 硬重启失败: \(error)")
        }
    }

    @objc private func handleAudioRouteChange(notification: Notification) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let needsMic = self.isHandsFreeMode || self.isTalking
            self.setupAudioEngine(needsMic: needsMic)
            
            if self.isHandsFreeMode {
                self.startContinuousListening()
            } else if self.isTalking {
                self.internalStartTalking()
            }
        }
    }

    public func startTalking() {
        guard isRunning, hasConnectedPeers, !isTalking else { return }
        micRequest {
            self.internalStartTalking()
        }
    }
    
    func micRequest(authorized:PTActionTask? = nil) {
        PTPermission.microphone.request {
            PTGCDManager.shared.runOnMain {
                switch PTPermission.microphone.status {
                case .authorized:
                    authorized?()
                case .notDetermined:
                    self.micRequest(authorized: authorized)
                default:
                    PTNSLogConsole("❌ [音频引擎] 麦克风权限被拒绝，无法开启对讲！")
                    self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_mic_denied")) // 你可以在语言包里加个提示
                }
            }
        }
    }
    
    private func internalStartTalking() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            if !self.isHandsFreeMode {
                self.setupAudioEngine(needsMic: true)
            }
            self.playerNode.pause()
            
            let inputNode = self.audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            
            let hardwareFormat = inputNode.outputFormat(forBus: 0)
            guard hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 else {
                PTNSLogConsole("❌ [音频引擎] 无法获取麦克风硬件格式，正在硬重启...")
                self.restartEngineHard()
                return
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] (buffer, time) in
                guard let self = self else { return }
                
                buffer.applyGain(self.micVolumeMultiplier)
                
                if buffer.format == self.commonFormat {
                    if let data = buffer.toData() {
                        self.sendAudioData(data)
                    }
                } else {
                    if let convertedBuffer = self.convert(buffer: buffer, from: buffer.format, to: self.commonFormat),
                       let data = convertedBuffer.toData() {
                        self.sendAudioData(data)
                    }
                }
            }
            
            // UI 更新调回主线程
            DispatchQueue.main.async {
                self.isTalking = true
                self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_radio"))
            }
        }
    }

    public func stopTalking() {
        guard isTalking else { return }
        // 立即在主线程切断状态，阻断 UI 滞后感
        isTalking = false
        self.isLocalUserSpeaking = false
        
        // 🌟 收尾操作转入串行后台，不怕狂点 PTT 崩溃！
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.audioEngine.inputNode.removeTap(onBus: 0)
            
            if !self.isHandsFreeMode {
                self.setupAudioEngine(needsMic: false)
            } else {
                self.safeStartPlayerNode()
            }
            
            DispatchQueue.main.async {
                self.updateStatusAndBroadcast(self.session.connectedPeers.isEmpty ? PTDashboardConfig.languageFunc(text: "ptt_ready_connect") : PTDashboardConfig.languageFunc(text: "ptt_ready_connected"))
            }
        }
    }

    private func sendAudioData(_ data: Data) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        do {
            // 使用 do-catch，如果发送失败，立刻在控制台打印出致命原因！
            try session.send(data, toPeers: peers, with: .unreliable)
        } catch {
            PTNSLogConsole("❌ 语音数据发送彻底失败: \(error.localizedDescription)")
        }
    }
    
    fileprivate func receiveAndPlay(data: Data) {
        guard !isTalking else { return }
        
        // 用全网统一的 commonFormat 去解码对方发来的 Data
        if let buffer = data.toPCMBuffer(format: commonFormat) {
            audioQueue.async { [weak self] in
                self?.safeStartPlayerNode()
                self?.playerNode.scheduleBuffer(buffer, completionHandler: nil)
            }
        }
    }
    
    // MARK: - 引擎内部音频重采样器
    private func convert(buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        
        // 计算转换后的 Buffer 应该多大
        let sampleRateRatio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameCapacity) * sampleRateRatio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        // 执行重采样转换
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .haveData || status == .inputRanDry {
            return outputBuffer
        }
        return nil
    }
    
    public func toggleHandsFreeMode(isOn: Bool) {
        guard !isOn || (isRunning && hasConnectedPeers) else { return }
        isHandsFreeMode = isOn
        
        if isOn {
            PTNSLogConsole("🎙️ [音频引擎] 已开启免提声控模式")
            startContinuousListening()
        } else {
            PTNSLogConsole("🎙️ [音频引擎] 已关闭免提模式，恢复按键对讲")
            stopContinuousListening()
        }
    }
    
    private func startContinuousListening() {
        // 同样加入权限校验
        micRequest { [weak self] in
            guard let self = self else { return }
            
            self.audioQueue.async {
                self.setupAudioEngine(needsMic: true)
                
                let inputNode = self.audioEngine.inputNode
                inputNode.removeTap(onBus: 0)
                
                let hardwareFormat = inputNode.outputFormat(forBus: 0)
                guard hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 else {
                    self.restartEngineHard()
                    return
                }
                
                inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self = self] (buffer, time) in
                    guard let self = self, self.isHandsFreeMode else { return }
                    
                    let currentVolume = buffer.calculateRMS()
                    let now = Date()
                    var isCurrentlySpeaking = false
                    
                    if currentVolume > self.voiceThreshold {
                        self.lastSpokenTime = now
                        isCurrentlySpeaking = true
                    } else if now.timeIntervalSince(self.lastSpokenTime) < self.voxHangTime {
                        isCurrentlySpeaking = true
                    }
                    
                    // 防刷屏状态更新机制
                    if self.isLocalUserSpeaking != isCurrentlySpeaking {
                        DispatchQueue.main.async { self.isLocalUserSpeaking = isCurrentlySpeaking }
                    }
                    
                    if isCurrentlySpeaking {
                        if !self.isTalking {
                            DispatchQueue.main.async {
                                self.isTalking = true
                                self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_radio"))
                            }
                            // 后台默默暂停收音机，防回音
                            self.audioQueue.async { self.playerNode.pause() }
                        }
                        
                        buffer.applyGain(self.micVolumeMultiplier)
                        
                        if buffer.format == self.commonFormat {
                            if let data = buffer.toData() { self.sendAudioData(data) }
                        } else {
                            if let convertedBuffer = self.convert(buffer: buffer, from: buffer.format, to: self.commonFormat),
                               let data = convertedBuffer.toData() {
                                self.sendAudioData(data)
                            }
                        }
                        
                    } else {
                        if self.isTalking {
                            DispatchQueue.main.async {
                                self.isTalking = false
                                self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"))
                            }
                            self.audioQueue.async { self.playerNode.play() }
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"))
                }
            }
        }
    }
    
    private func stopContinuousListening() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.audioEngine.inputNode.removeTap(onBus: 0)
            
            DispatchQueue.main.async {
                self.isTalking = false
                self.isLocalUserSpeaking = false
            }
            
            self.setupAudioEngine(needsMic: false)
            
            DispatchQueue.main.async {
                self.updateStatusAndBroadcast(self.session.connectedPeers.isEmpty ? PTDashboardConfig.languageFunc(text: "ptt_ready_connect") : PTDashboardConfig.languageFunc(text: "ptt_ready_connected"))
            }
        }
    }
    
    private func updateStatusAndBroadcast(_ status: String) {
        self.currentStatusText = status
        self.delegate?.intercomManager(self, didChangeStatus: status)
    }
    
    func globalStatusChangeSet() {
        var peerStates: [PeerLiveState] = []
        for peer in self.activePeers {
            // 如果你在内存字典里有这个人的自定义头像，就去 App Group 拿到它的文件名；如果没有，传 ""
            var fileName = ""
            if let customAvatar = self.self.peerAvatars[peer] {
                // 这里调用我们上面的辅助方法存入共享沙盒，并拿到文件名
                fileName = savePeerAvatarToAppGroup(image: customAvatar, peerID: peer)
            }
            
            // 判断这个人当前是否正在说话 (基于 currentSpeakingPeers 集合)
            let isSpeaking = self.currentSpeakingPeers.contains(peer)
            
            let state = PeerLiveState(peerID: peer.displayName, peerName: peer.displayName, avatarFileName: fileName, isSpeaking: isSpeaking)
            peerStates.append(state)
        }
        
        let liveActivityPeers = isRunning && hasConnectedPeers ? peerStates : []

        // 只有已连接成员存在时才创建或更新锁屏组件；空群组会结束全部旧 Activity。
        let channel = PTDashboardConfig.languageFunc(text: "Team channel")
        let isTalking = self.isTalking
        let status = self.currentStatusText
        Task { @MainActor in
            PTLiveActivityManager.shared.syncIntercomActivity(
                channel: channel,
                isTalking: isTalking,
                status: status,
                peers: liveActivityPeers
            )
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: PTIntercomGlobalStatusChanged,
                object: nil,
                userInfo: [
                    "isRunning": self.isRunning,
                    "isTalking": self.isTalking,
                    "isHandsFree": self.isHandsFreeMode,
                    "peersCount": self.connectedPeersCount,
                    "otherMemberTalking":self.otherMemberTalking,
                    "statusText":self.currentStatusText
                ]
            )
        }
    }
    
    public func restoreIntercomStateAtLaunch() {
        // 进程重启后 Activity 引用会丢失，启动阶段先清理系统中可能残留的旧活动。
        Task { @MainActor in
            PTLiveActivityManager.shared.stopIntercomActivity()
        }

        let shouldAutoStart = UserDefaults.standard.bool(forKey: intercomPowerStateKey)
        if shouldAutoStart {
            PTNSLogConsole("🚀 [音频引擎] 检测到上次对讲机为开启状态，正在后台自动组网...")
            startOfflineIntercom()
        } else {
            PTNSLogConsole("💤 [音频引擎] 上次对讲机为关闭状态，保持静默，省电模式")
        }
    }
    
    private func savePeerAvatarToAppGroup(image: UIImage, peerID: MCPeerID) -> String {
        let fileName = "avatar_\(peerID.displayName).jpg"
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return "" }
        
        let fileURL = groupURL.appendingPathComponent(fileName)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
            return fileName
        }
        return ""
    }
}

// MARK: - 组网代理回调
extension PTLocalIntercomManager: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if session.connectedPeers.contains(peerID) || self.activePeers.contains(peerID) || self.connectingPeers.contains(peerID) {
            self.delegate?.intercomManager(self, didUpdatePeers: self.activePeers.count)
            return
        }
        guard let peerUUID = info?["uuid"], peerUUID != self.myUUID else {
            PTNSLogConsole("⚠️ [组网] 发现非法或幽灵节点，已抛弃")
            return
        }

        if self.myUUID > peerUUID {
            self.connectingPeers.insert(peerID)
            PTNSLogConsole("➡️ [组网决断] 我方准备发起邀请给: \(peerID.displayName)")
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        } else {
            PTNSLogConsole("⬅️ [组网决断] 我方(UUID小) 保持安静，等待 \(peerID.displayName) 拉我...")
        }
    }
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            // 忽略旧会话在重新组网或关闭后的迟到回调，避免复活过期成员。
            guard session === self.session else { return }

            let stateName: String
            switch state {
            case .notConnected: stateName = "未连接"
            case .connecting: stateName = "连接中"
            case .connected: stateName = "已连接"
            @unknown default: stateName = "未知"
            }
            PTNSLogConsole("📡 [MCSession] 车友 \(peerID.displayName) 底层网络跳变: \(stateName)")

            switch state {
            case .connected:
                guard self.isRunning else { return }
                self.connectingPeers.remove(peerID)
                
                if !self.activePeers.contains(peerID) {
                    self.activePeers.append(peerID)
                }
                if self.activePeers.count == 1 {
                    self.startSpeakingDetector()
                    self.startPingTimer()
                }
                // 有车友加入网络
                self.updateStatusAndBroadcast(PTDashboardConfig.language(key: "ptt_ready_connected_name", peerID.displayName))
                self.delegate?.intercomManager(self, didUpdatePeers: self.activePeers.count)
                self.delegate?.intercomManager(self, didUpdatePeerList: self.activePeers)

                let currentAvatar = self.currentMyAvatar()
                self.sendMyAvatar(to: peerID, avatarImage: currentAvatar)
                
            case .notConnected:
                // 有车友掉线或主动离开网络
                self.connectingPeers.remove(peerID)
                PTNSLogConsole("❌ [组网] \(peerID.displayName) 已断开连接")
                // 检查车队里是否还有其他人
                self.activePeers.removeAll { $0 == peerID }
                self.lastReceivedAudio.removeValue(forKey: peerID) // 清理掉线的人
                self.peerAvatars.removeValue(forKey: peerID)
                if self.activePeers.isEmpty {
                    self.stopSpeakingDetector()
                    self.stopPingTimer()
                    if self.isHandsFreeMode {
                        self.toggleHandsFreeMode(isOn: false)
                    }
                    // 车队空了，恢复到等待状态
                    self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_ready_connect"))
                } else {
                    // 车队里还有人，拿当前列表里的第一个车友名字来显示
                    if let remainingPeer = self.activePeers.first {
                        self.updateStatusAndBroadcast(PTDashboardConfig.language(key: "ptt_ready_connected_name", remainingPeer.displayName))
                    }
                }
                self.delegate?.intercomManager(self, didUpdatePeers: self.activePeers.count)
                self.delegate?.intercomManager(self, didUpdatePeerList: self.activePeers)

            case .connecting:
                // 正在尝试建立连接时（可选：通常底层瞬间完成，这里仅打印日志方便调试）
                PTNSLogConsole("⏳ [组网] 正在与 \(peerID.displayName) 建立连接...")
                
            @unknown default:
                break
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let text = String(data: data, encoding: .utf8) {
            if text.hasPrefix("PING:") {
                let pongText = text.replacingOccurrences(of: "PING:", with: "PONG:")
                if let pongData = pongText.data(using: .utf8) {
                    try? session.send(pongData, toPeers: [peerID], with: .reliable)
                }
                return // 🚨 拦截完毕，这是心跳包，直接 Return！
                
            } else if text.hasPrefix("PONG:") {
                let timeString = text.replacingOccurrences(of: "PONG:", with: "")
                if let sentTime = Double(timeString) {
                    let latencyMs = Int((Date().timeIntervalSince1970 - sentTime) * 1000)
                    let signalLevel: PTNetworkSignalLevel
                    if latencyMs < 50 { signalLevel = .strong }
                    else if latencyMs < 150 { signalLevel = .normal }
                    else { signalLevel = .weak }
                    
                    DispatchQueue.main.async {
                        self.delegate?.intercomManager(self, didUpdateNetworkStatusFor: peerID, latency: latencyMs, signal: signalLevel)
                    }
                }
                return // 🚨 拦截完毕，这是心跳包，直接 Return！
            } else if text.hasPrefix("LOC:") {
                // 🌟 新增：拦截并解析位置数据包
                let jsonString = text.replacingOccurrences(of: "LOC:", with: "")
                if let jsonData = jsonString.data(using: .utf8),
                   var location = try? JSONDecoder().decode(PTPeerLocation.self, from: jsonData) {
                    
                    guard location.originalSender != self.myUUID else { return }
                    
                    let now = Date()
                    self.processedMessageIDs = self.processedMessageIDs.filter { now.timeIntervalSince($0.value) < 10 }
                    
                    if self.processedMessageIDs.keys.contains(location.messageID) {
                        return
                    }
                    
                    // 记录这个新的包，打上时间戳
                    self.processedMessageIDs[location.messageID] = now
                    
                    // 利用全局通知将位置发送给外部地图控制器
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: PTPeerLocationDidUpdateNotification,
                            object: nil,
                            userInfo: [
                                "peerID": peerID,
                                "location": location
                            ]
                        )
                    }
                    
                    if location.ttl > 0 {
                        location.ttl -= 1 // 消耗掉一次跳数寿命
                        
                        // 重新打包降级后的数据
                        if let relayData = try? JSONEncoder().encode(location),
                           let relayString = String(data: relayData, encoding: .utf8) {
                            
                            let payloadData = "LOC:\(relayString)".data(using: .utf8)!
                            
                            // 找到除发给我这条消息的兄弟之外的其他在线节点
                            let otherPeers = session.connectedPeers.filter { $0 != peerID }
                            
                            if !otherPeers.isEmpty {
                                // 以接力赛的方式扔给下一个人！
                                try? session.send(payloadData, toPeers: otherPeers, with: .unreliable)
                                PTNSLogConsole("📡 [Mesh 中继] 成功将 \(location.originalSender) 的坐标继续向后接力！剩余跳数: \(location.ttl)")
                            }
                        }
                    }
                }
                return // 🚨 拦截完毕，不能让定位数据流入音频播放器！
            }
        }
        
        // 🌟 7. 解决头像错误闪烁：只有确实没有被上面的 Return 拦截，走到这里的才是真正的音频流！
        // 此时我们才记录它的说话时间！
        lastReceivedAudio[peerID] = Date()
        self.receiveAndPlay(data: data)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { }
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        guard error == nil,
              let url = localURL,
              resourceName == "AVATAR_IMAGE" else { return }
        
        do {
            // 从临时路径读取收到的图片数据
            let imageData = try Data(contentsOf: url)
            if let receivedImage = UIImage(data: imageData) {
                PTNSLogConsole("🖼️ [头像传输] 成功接收到队友 \(peerID.displayName) 的头像！")
                
                self.peerAvatars[peerID] = receivedImage
                self.globalStatusChangeSet()
                // 🌟 发送全局通知，把照片扔给外部 UI 进行刷新
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: PTPeerAvatarDidUpdateNotification,
                        object: nil,
                        userInfo: [
                            "peerID": peerID,
                            "avatarImage": receivedImage
                        ]
                    )
                }
            }
        } catch {
            PTNSLogConsole("❌ [头像传输] 读取接收到的文件失败: \(error)")
        }
    }
}

// MARK: - 底层内存转换扩展
extension AVAudioPCMBuffer {
    func toData() -> Data? {
        let channels = UnsafeBufferPointer(start: self.floatChannelData, count: Int(self.format.channelCount))
        return Data(bytes: channels[0], count: Int(self.frameLength) * MemoryLayout<Float>.size)
    }
    
    func calculateRMS() -> Float {
        guard let channelData = self.floatChannelData else { return 0.0 }
        let channelDataValue = channelData[0]
        let frames = Int(self.frameLength)
        
        var rms: Float = 0.0
        for i in 0..<frames {
            let sample = channelDataValue[i]
            rms += sample * sample
        }
        rms = sqrt(rms / Float(frames))
        return rms
    }
    
    func applyGain(_ multiplier: Float) {
        // 如果倍数是 1.0 就不浪费 CPU 算力了
        guard multiplier != 1.0, let floatChannelData = self.floatChannelData else { return }
        
        let channelCount = Int(self.format.channelCount)
        let frames = Int(self.frameLength)
        
        for channel in 0..<channelCount {
            let channelData = floatChannelData[channel]
            for i in 0..<frames {
                // 1. 将音频波幅乘以放大倍数
                var sample = channelData[i] * multiplier
                
                // 2. 硬件防爆音裁剪 (Hard Clipping)
                // 保证数值绝对不能溢出 -1.0 到 1.0 的安全区，否则会导致设备扬声器破音
                if sample > 1.0 { sample = 1.0 }
                else if sample < -1.0 { sample = -1.0 }
                
                // 3. 写回内存
                channelData[i] = sample
            }
        }
    }
}

extension Data {
    func toPCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCapacity = UInt32(self.count / MemoryLayout<Float>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        buffer.frameLength = frameCapacity
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(format.channelCount))
        self.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress {
                channels[0].update(from: baseAddress.assumingMemoryBound(to: Float.self), count: Int(frameCapacity))
            }
        }
        return buffer
    }
}
