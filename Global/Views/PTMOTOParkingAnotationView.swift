//
//  PTMOTOParkingAnotationView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 22/7/2026.
//

import UIKit
import PooTools
import AMapNaviKit

class PTMOTOParkingAnotationView: MAAnnotationView {
    
    override init!(annotation: (any MAAnnotation)!, reuseIdentifier: String!) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
