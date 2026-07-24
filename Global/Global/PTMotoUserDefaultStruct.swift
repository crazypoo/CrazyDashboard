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
}
