//
//  xp400WidgetBundle.swift
//  xp400Widget
//
//  Created by 邓杰豪 on 30/7/2026.
//

import WidgetKit
import SwiftUI

@main
struct xp400WidgetBundle: WidgetBundle {
    var body: some Widget {
        XP400Widget()
        MotoNaviLiveActivity()
        MotoIntercomLiveActivity()
    }
}
