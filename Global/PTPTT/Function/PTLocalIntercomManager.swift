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

// MARK: - 状态回调协议，用于通知 UI 更新
public protocol PTLocalIntercomDelegate: AnyObject {
    func intercomManager(_ manager: PTLocalIntercomManager, didChangeStatus status: String)
    func intercomManager(_ manager: PTLocalIntercomManager, didUpdatePeers count: Int)
}

@objcMembers
public class PTLocalIntercomManager: NSObject {
    
    public static let shared = PTLocalIntercomManager()
    public weak var delegate: PTLocalIntercomDelegate?
    
    // 多点连接组件
    private let serviceType = "pt-moto-voice"
    private let myPeerId: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    // 音频引擎组件
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private let commonFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
    public private(set) var isTalking: Bool = false
    
    public private(set) var isHandsFreeMode: Bool = false
    public var voiceThreshold: Float = 0.05

    public private(set) var isRunning: Bool = false
    public var connectedPeersCount: Int {
        return session?.connectedPeers.count ?? 0
    }
    public private(set) var currentStatusText: String = PTDashboardConfig.languageFunc(text: "ptt_ready_connect")
    private let intercomPowerStateKey = "PTIntercomPowerStateKey"
    
    public var micVolumeMultiplier: Float = 3.0
    
    private override init() {
        self.myPeerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        setupMultipeer()
        setupAudioSession()
        setupAudioEngine()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func setupMultipeer() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        browser.delegate = self
    }
    
    public func startOfflineIntercom() {
        guard !isRunning else { return }
        isRunning = true
        
        UserDefaults.standard.set(true, forKey: intercomPowerStateKey)
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        
        currentStatusText = PTDashboardConfig.languageFunc(text: "ptt_find_friend")
        updateStatusAndBroadcast(currentStatusText)
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
        
        currentStatusText = PTDashboardConfig.languageFunc(text: "ptt_close")
        updateStatusAndBroadcast(currentStatusText)
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
        
        // 安全地移除 Tap
        audioEngine.inputNode.removeTap(onBus: 0)
        
        playerNode.play() // 恢复接收状态
        updateStatusAndBroadcast(session.connectedPeers.isEmpty ? PTDashboardConfig.languageFunc(text: "ptt_ready_connect") : PTDashboardConfig.languageFunc(text: "ptt_ready_connected"))
    }

    private func sendAudioData(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }
    
    fileprivate func receiveAndPlay(data: Data) {
        guard !isTalking else { return }
        
        // 用全网统一的 commonFormat 去解码对方发来的 Data
        if let buffer = data.toPCMBuffer(format: commonFormat) {
            if !playerNode.isPlaying { playerNode.play() }
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
        guard !isTalking else { return }
        if !audioEngine.isRunning { setupAudioEngine() }
        
        playerNode.pause() // 停止播放，防止回音
        
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
            
            // 🌟 只有说话声音盖过了背景阈值，才处理和发送数据！
            if currentVolume > self.voiceThreshold {
                
                buffer.applyGain(self.micVolumeMultiplier)
                
                if buffer.format == self.commonFormat {
                    if let data = buffer.toData() { self.sendAudioData(data) }
                } else {
                    if let convertedBuffer = self.convert(buffer: buffer, from: buffer.format, to: self.commonFormat),
                       let data = convertedBuffer.toData() {
                        self.sendAudioData(data)
                    }
                }
            }
        }
        
        isTalking = true
        updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_hand_free_listening"))
    }
    
    private func stopContinuousListening() {
        guard isTalking else { return }
        isTalking = false
        
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.play()
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
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.intercomManager(self, didUpdatePeers: session.connectedPeers.count)
            switch state {
            case .connected:
                // 有车友加入网络
                self.updateStatusAndBroadcast(PTDashboardConfig.language(key: "ptt_ready_connected_name", peerID.displayName))
                
            case .notConnected:
                // 有车友掉线或主动离开网络
                PTNSLogConsole("❌ [组网] \(peerID.displayName) 已断开连接")
                // 检查车队里是否还有其他人
                if session.connectedPeers.isEmpty {
                    // 车队空了，恢复到等待状态
                    self.updateStatusAndBroadcast(PTDashboardConfig.languageFunc(text: "ptt_ready_connect"))
                } else {
                    // 车队里还有人，拿当前列表里的第一个车友名字来显示
                    if let remainingPeer = session.connectedPeers.first {
                        self.updateStatusAndBroadcast(PTDashboardConfig.language(key: "ptt_ready_connected_name", remainingPeer.displayName))
                    }
                }
            case .connecting:
                // 正在尝试建立连接时（可选：通常底层瞬间完成，这里仅打印日志方便调试）
                PTNSLogConsole("⏳ [组网] 正在与 \(peerID.displayName) 建立连接...")
                
            @unknown default:
                break
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
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
