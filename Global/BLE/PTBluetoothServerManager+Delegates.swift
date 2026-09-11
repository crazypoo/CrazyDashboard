//
//  PTBluetoothServerManager+Delegates.swift
//  CrazyDashboard
//
//  EN: Keeps weak delegate registration and cleanup isolated from transport state.
//  ES: Aísla el registro y la limpieza de delegados débiles del estado de transporte.
//  中文：将弱代理注册和清理与传输状态隔离。
//
import UIKit
import CoreBluetooth
import PooTools
import UserNotifications

//MARK: Delegate
extension PTBluetoothServerManager {
    public func addDelegate(_ delegate: PTBLEDashboardDelegate) {
        cleanupDelegates()
        let isAlreadyAdded = delegates.contains { $0.delegate === delegate }
        if !isAlreadyAdded {
            delegates.append(WeakDelegateWrapper(delegate))
        }
    }
    
    private func cleanupDelegates() {
        delegates.removeAll { $0.delegate == nil }
    }
    
    public func removeDelegate(_ delegate: PTBLEDashboardDelegate) {
        delegates.removeAll { $0.delegate === delegate || $0.delegate == nil }
    }
}

