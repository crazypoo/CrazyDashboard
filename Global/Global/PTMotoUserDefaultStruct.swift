//
//  PTMotoUserDefaultStruct.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 21/7/2026.
//

import UIKit
import PooTools

struct PTMotoUserDefaultStruct {
    @PTUserDefault(withKey: "PTAppFirst", defaultValue: true) public static var appFirst:Bool
    @PTUserDefault(withKey: "PTUserLanguage", defaultValue: "zh") public static var userSetLanguage:String
    @PTUserDefault(withKey: "ble_data_hex_get", defaultValue: false) public static var BleTestDataGet:Bool
    @PTUserDefault(withKey: "NavMute", defaultValue: false) public static var NavMute:Bool
    @PTUserDefault(withKey: "MotoLinkedAPP", defaultValue: false) public static var MotoLinkedAPP:Bool
    @PTUserDefault(withKey: "CoachFirst", defaultValue: true) public static var CoachFirst:Bool
    @PTUserDefault(withKey: "OBDID", defaultValue: "") public static var OBDID:String
    // EN: Automatic OBD connection is opt-in so app launch never starts a scan implicitly.
    // ES: La conexión OBD automática requiere activación explícita para que el lanzamiento no inicie un escaneo.
    // 中文：OBD 自动连接必须显式开启，确保 App 启动不会隐式开始扫描。
    @PTUserDefault(withKey: "OBDAutoConnectEnabled", defaultValue: false) public static var OBDAutoConnectEnabled:Bool
}
