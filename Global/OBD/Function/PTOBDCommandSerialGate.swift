//
//  PTOBDCommandSerialGate.swift
//  CrazyDashboard
//
//  Build69 Hotfix
//  Serializes ELM/OBD request-response transactions so the transport's
//  single response continuation cannot be overwritten by concurrent callers.
//

import Foundation

/// ELM327 is a request/response serial transport. Even if multiple upper
/// layers are asynchronous, only one command may own the prompt/response
/// channel at a time.
actor PTOBDCommandSerialGate {

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isLocked = false
            return
        }

        let next = waiters.removeFirst()
        next.resume()
    }
}
