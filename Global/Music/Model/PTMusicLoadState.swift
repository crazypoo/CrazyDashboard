//
//  PTMusicLoadState.swift
//  CrazyDashboard
//
//  English: UI-safe states and user-facing music errors.
//  Español: Estados seguros para UI y errores de música orientados al usuario.
//  中文：定义界面可消费的状态和用户可理解的音乐错误。
//

import Foundation
import MusicKit

public enum PTMusicUIError: String, Error, Equatable, Sendable {
    case authorizationRequired
    case accessDenied
    case accessRestricted
    case libraryUnavailable
    case subscriptionUnavailable
    case offline
    case timedOut
    case serviceUnavailable
    case emptyRequest
    case unknown

    public var userMessage: String {
        switch self {
        case .authorizationRequired:
            return NSLocalizedString("需要允许 Apple Music 访问权限", comment: "")
        case .accessDenied:
            return NSLocalizedString("Apple Music 访问已被拒绝，请在系统设置中开启", comment: "")
        case .accessRestricted:
            return NSLocalizedString("当前设备限制了 Apple Music 访问", comment: "")
        case .libraryUnavailable:
            return NSLocalizedString("Apple Music 资料库暂不可用", comment: "")
        case .subscriptionUnavailable:
            return NSLocalizedString("当前 Apple Music 订阅无法播放此内容", comment: "")
        case .offline:
            return NSLocalizedString("网络不可用，请检查连接后重试", comment: "")
        case .timedOut:
            return NSLocalizedString("Apple Music 响应超时，请重试", comment: "")
        case .serviceUnavailable:
            return NSLocalizedString("Apple Music 暂时无法响应，请稍后重试", comment: "")
        case .emptyRequest:
            return NSLocalizedString("请输入搜索内容", comment: "")
        case .unknown:
            return NSLocalizedString("音乐数据加载失败，请重试", comment: "")
        }
    }

    public static func map(_ error: Error) -> PTMusicUIError {
        if let musicError = error as? PTMusicUIError {
            return musicError
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet:
                return .offline
            default:
                break
            }
        }

        return .serviceUnavailable
    }
}

public enum PTMusicAuthorizationCapability: String, Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    public init(status: MusicAuthorization.Status) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .restricted
        }
    }
}

public enum PTMusicLoadState: Equatable, Sendable {
    case idle
    case loading(PTMusicQueryKey)
    case content(PTMusicQueryKey)
    case empty(PTMusicQueryKey)
    case failed(PTMusicQueryKey, PTMusicUIError)
    case timedOut(PTMusicQueryKey)

    public var queryKey: PTMusicQueryKey? {
        switch self {
        case .idle:
            return nil
        case .loading(let key),
             .content(let key),
             .empty(let key),
             .failed(let key, _),
             .timedOut(let key):
            return key
        }
    }
}
