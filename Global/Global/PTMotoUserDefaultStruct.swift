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
}
