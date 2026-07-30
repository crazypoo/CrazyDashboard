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
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat!
    
    private override init() {
        self.myPeerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        setupMultipeer()
        setupAudioSession()
        setupAudioEngine()
    }
    
    // MARK: - 1. 组网逻辑
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
        delegate?.intercomManager(self, didChangeStatus: "正在扫描附近的车友...")
    }
    
    public func stopOfflineIntercom() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        audioEngine.stop()
        delegate?.intercomManager(self, didChangeStatus: "对讲机已关闭")
    }
    
    // MARK: - 2. 音频环境与引擎搭建
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            PTNSLogConsole("音频Session配置失败: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let inputNode = audioEngine.inputNode
        let outputNode = audioEngine.outputNode
        audioFormat = inputNode.inputFormat(forBus: 0)
        
        audioEngine.connect(playerNode, to: outputNode, format: audioFormat)
        
        do {
            try audioEngine.start()
        } catch {
            PTNSLogConsole("音频引擎启动失败: \(error)")
        }
    }
    
    // MARK: - 3. 对讲操作 (录音与发送)
    public func startTalking() {
        playerNode.pause() // 说话时禁止播放，防回音
        
        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: audioFormat) { [weak self] (buffer, time) in
            if let data = buffer.toData() {
                self?.sendAudioData(data)
            }
        }
        delegate?.intercomManager(self, didChangeStatus: "正在广播语音...")
    }
    
    public func stopTalking() {
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.play() // 恢复接收状态
        delegate?.intercomManager(self, didChangeStatus: session.connectedPeers.isEmpty ? "等待连接" : "已连接，随时对讲")
    }
    
    private func sendAudioData(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }
    
    // MARK: - 4. 接收与播放
    fileprivate func receiveAndPlay(data: Data) {
        // 如果正在说话，过滤掉收到的声音
        guard !audioEngine.inputNode.numberOfInputs.isMultiple(of: 0) else { return }
        
        if let buffer = data.toPCMBuffer(format: audioFormat) {
            if !playerNode.isPlaying { playerNode.play() }
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
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
            if state == .connected {
                self.delegate?.intercomManager(self, didChangeStatus: "已连接到: \(peerID.displayName)")
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
