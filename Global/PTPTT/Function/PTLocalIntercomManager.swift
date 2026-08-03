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

public enum PTNetworkSignalLevel {
    case strong // 满格绿信号 (< 50ms)
    case normal // 两格黄信号 (50 ~ 150ms)
    case weak   // 一格红信号 (> 150ms)
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
    public private(set) var isTalking: Bool = false
    
    public private(set) var isHandsFreeMode: Bool = false
    public var voiceThreshold: Float = 0.009
    private var lastSpokenTime: Date = Date.distantPast
    private let voxHangTime: TimeInterval = 0.8
    
    public private(set) var isRunning: Bool = false
    
    public private(set) var currentStatusText: String = PTDashboardConfig.languageFunc(text: "ptt_ready_connect")
    private let intercomPowerStateKey = "PTIntercomPowerStateKey"
    
    public var micVolumeMultiplier: Float = 3.0
    
    private var lastReceivedAudio: [MCPeerID: Date] = [:]
    private var currentSpeakingPeers: Set<MCPeerID> = []
    private var speakingTimer: Timer?

    private var pingTimer: Timer?
    
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

    public private(set) var activePeers: [MCPeerID] = []
    private var connectingPeers: Set<MCPeerID> = []
    
    public var connectedPeersCount: Int {
        return activePeers.count
    }

    private lazy var myUUID: String = {
        let key = "PT_Device_Unique_UUID"
        if let savedUUID = UserDefaults.standard.string(forKey: key) { return savedUUID }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: key)
        return newUUID
    }()

    private override init() {
        super.init()
        setupPeerID()
        setupMultipeer()
        setupAudioSession()
        setupAudioEngine()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func setupPeerID() {
        let peerIDKey = "PT_SavedMCPeerID"
        if let data = UserDefaults.standard.data(forKey: peerIDKey),
           let savedPeer = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            self.myPeerId = savedPeer
            PTNSLogConsole("✅ [组网] 成功读取固化身份: \(savedPeer.displayName)")
        } else {
            let newPeer = MCPeerID(displayName: UIDevice.current.name)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newPeer, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: peerIDKey)
            }
            self.myPeerId = newPeer
            PTNSLogConsole("🆕 [组网] 生成新身份: \(newPeer.displayName)")
        }
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
        isRunning = true
        
        UserDefaults.standard.set(true, forKey: intercomPowerStateKey)
        
        setupMultipeer()
        
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        
        currentStatusText = PTDashboardConfig.languageFunc(text: "ptt_find_friend")
        updateStatusAndBroadcast(currentStatusText)
        startSpeakingDetector()
        startPingTimer()
    }
    
    public func stopOfflineIntercom() {
        guard isRunning else { return }
        isRunning = false
        
        UserDefaults.standard.set(false, forKey: intercomPowerStateKey)
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        audioEngine.stop()
        
        // 如果开启了免提，重置它
        isHandsFreeMode = false
        isTalking = false
        isLocalUserSpeaking = false // 重置状态
        
        currentStatusText = PTDashboardConfig.languageFunc(text: "ptt_close")
        updateStatusAndBroadcast(currentStatusText)
        stopSpeakingDetector()
        stopPingTimer()
    }
    
    private func startSpeakingDetector() {
        stopSpeakingDetector()
        // 每 0.2 秒轮询一次，判断有没有人很久没发声音了
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
            // 如果在过去 0.5 秒内收到过他的声音，判定为正在说话！
            if now.timeIntervalSince(lastTime) < 0.5 {
                newSpeaking.insert(peer)
            }
        }
        
        // 状态发生改变时，通知 UI
        if newSpeaking != currentSpeakingPeers {
            currentSpeakingPeers = newSpeaking
            DispatchQueue.main.async {
                self.delegate?.intercomManager(self, speakingPeersChanged: Array(self.currentSpeakingPeers))
            }
        }
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker,.allowBluetoothA2DP, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            PTNSLogConsole("音频Session配置失败: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        audioEngine.stop() // 停掉旧的
        
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: commonFormat)
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
        PTGCDManager.shared.runOnMain {
            self.setupAudioEngine()
        }
    }

    public func startTalking() {
        guard !isTalking else { return }
        
        if !audioEngine.isRunning {
            setupAudioEngine()
        }
        playerNode.pause()
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] (buffer, time) in
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
        
        isTalking = true
        updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_radio"))
    }
    
    public func stopTalking() {
        guard isTalking else { return }
        isTalking = false
        self.isLocalUserSpeaking = false // 重置状态
        // 安全地移除 Tap
        audioEngine.inputNode.removeTap(onBus: 0)
        
        safeStartPlayerNode()
        updateStatusAndBroadcast(session.connectedPeers.isEmpty ? PTDashboardConfig.languageFunc(text: "ptt_ready_connect") : PTDashboardConfig.languageFunc(text: "ptt_ready_connected"))
    }

    private func sendAudioData(_ data: Data) {
        let peers = activePeers
        guard !peers.isEmpty else { return }
        PTNSLogConsole(">>>>>>>>>>>>>>>> 发送了 \(data.count) bytes 数据")
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
            safeStartPlayerNode()
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
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
        if !audioEngine.isRunning { setupAudioEngine() }
                
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0 else {
            restartEngineHard()
            return
        }
        
        // 挂载长期的监听 Tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] (buffer, time) in
            guard let self = self, self.isHandsFreeMode else { return }
            
            // 🌟 核心：计算当前瞬间的音量
            let currentVolume = buffer.calculateRMS()
            
             PTNSLogConsole("🎤 实测音量: \(currentVolume) | 目标阈值: \(self.voiceThreshold)")
            let now = Date()
            var isCurrentlySpeaking = false
            
            // 🌟 只有说话声音盖过了背景阈值，才处理和发送数据！
            if currentVolume > self.voiceThreshold {
                
                self.lastSpokenTime = now
                isCurrentlySpeaking = true
            } else if now.timeIntervalSince(self.lastSpokenTime) < self.voxHangTime {
                // 音量虽然掉下来了，但还在 0.8 秒的防断流延时保护期内，继续发送！
                isCurrentlySpeaking = true
            }
            
            self.isLocalUserSpeaking = isCurrentlySpeaking
            
            if isCurrentlySpeaking {
                
                // 【状态切换】：如果是刚刚开口，立刻切断对方的声音（防回音），并广播状态
                if !self.isTalking {
                    self.isTalking = true
                    DispatchQueue.main.async { self.playerNode.pause() }
                    self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_radio"))
                }
                
                // 【数据发送】：应用音量放大，并封包发送
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
                // 【状态切换】：如果是刚刚停下（过了 0.8 秒保护期），恢复接收对方的声音
                if self.isTalking {
                    self.isTalking = false
                    DispatchQueue.main.async { self.playerNode.play() }
                    self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"))
                }
                
            }
        }
        
        updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"))
    }
    
    private func stopContinuousListening() {
        audioEngine.inputNode.removeTap(onBus: 0)
        isTalking = false
        self.isLocalUserSpeaking = false // 重置状态
        if !playerNode.isPlaying { playerNode.play() }
        updateStatusAndBroadcast(session.connectedPeers.isEmpty ? PTDashboardConfig.languageFunc(text: "ptt_ready_connect") : PTDashboardConfig.languageFunc(text: "ptt_ready_connected"))
    }
    
    private func updateStatusAndBroadcast(_ status: String) {
        // 更新本地记录
        self.currentStatusText = status
        
        // 1. 通知原本的 Delegate (比如 PTPTTViewController)
        self.delegate?.intercomManager(self, didChangeStatus: status)
        
        // 2. 广播给全 App (其他界面如地图、仪表盘也能收到)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: PTIntercomGlobalStatusChanged,
                object: nil,
                userInfo: [
                    "isRunning": self.isRunning,
                    "isTalking": self.isTalking,
                    "isHandsFree": self.isHandsFreeMode,
                    "peersCount": self.connectedPeersCount
                ]
            )
        }
    }
    
    public func restoreIntercomStateAtLaunch() {
        // 读取上一次的电源状态，默认为 false（即新用户首次打开时不强制开启）
        let shouldAutoStart = UserDefaults.standard.bool(forKey: intercomPowerStateKey)
        
        if shouldAutoStart {
            PTNSLogConsole("🚀 [音频引擎] 检测到上次对讲机为开启状态，正在后台自动组网...")
            startOfflineIntercom()
        } else {
            PTNSLogConsole("💤 [音频引擎] 上次对讲机为关闭状态，保持静默，省电模式")
        }
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

        // 🌟 核心突破 3：字符串严格对比！谁的 UUID 字母大，谁就当“队长”去主动拉人！
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
                self.connectingPeers.remove(peerID)
                
                if !self.activePeers.contains(peerID) {
                    self.activePeers.append(peerID)
                }
                // 有车友加入网络
                self.updateStatusAndBroadcast(PTDashboardConfig.language(key: "ptt_ready_connected_name", peerID.displayName))
                self.delegate?.intercomManager(self, didUpdatePeers: self.activePeers.count)
                self.delegate?.intercomManager(self, didUpdatePeerList: self.activePeers)

            case .notConnected:
                // 有车友掉线或主动离开网络
                self.connectingPeers.remove(peerID)
                PTNSLogConsole("❌ [组网] \(peerID.displayName) 已断开连接")
                // 检查车队里是否还有其他人
                self.activePeers.removeAll { $0 == peerID }
                self.lastReceivedAudio.removeValue(forKey: peerID) // 清理掉线的人
                if self.activePeers.isEmpty {
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
            }
        }
        
        // 🌟 7. 解决头像错误闪烁：只有确实没有被上面的 Return 拦截，走到这里的才是真正的音频流！
        // 此时我们才记录它的说话时间！
        lastReceivedAudio[peerID] = Date()
        self.receiveAndPlay(data: data)
    }

    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
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
