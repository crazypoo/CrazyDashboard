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
    private var isTalking: Bool = false
    
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
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        delegate?.intercomManager(self, didChangeStatus: PTDashboardConfig.languageFunc(text: "ptt_find_friend"))
    }
    
    public func stopOfflineIntercom() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        audioEngine.stop()
        delegate?.intercomManager(self, didChangeStatus: PTDashboardConfig.languageFunc(text: "ptt_close"))
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
        delegate?.intercomManager(self, didChangeStatus: PTDashboardConfig.languageFunc(text: "ptt_radio"))
    }
    
    public func stopTalking() {
        guard isTalking else { return }
        isTalking = false
        
        // 安全地移除 Tap
        audioEngine.inputNode.removeTap(onBus: 0)
        
        playerNode.play() // 恢复接收状态
        delegate?.intercomManager(self, didChangeStatus: session.connectedPeers.isEmpty ? PTDashboardConfig.languageFunc(text: "ptt_ready_connect") : PTDashboardConfig.languageFunc(text: "ptt_ready_connected"))
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
            if state == .connected {
                self.delegate?.intercomManager(self, didChangeStatus: PTDashboardConfig.language(key: "ptt_ready_connected_name", peerID.displayName))
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
