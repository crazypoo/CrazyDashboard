//
//  PTDataCollectedViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 24/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit

class PTDataCollectedViewController: PTMotoBaseViewController {

    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_inside_logo")
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()
    
    lazy var detailCollection:PTCollectionView = {
                                
        let collectionConfig = PTCollectionViewConfig()
        collectionConfig.viewType = .Custom
        collectionConfig.footerRefresh = false
        collectionConfig.topRefresh = false

        let view = PTCollectionView(viewConfig: collectionConfig)
        view.registerClassCells(classs: [PTTripDataCell.ID:PTTripDataCell.self])
        view.customerLayout = { sectionIndex,section in
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: 88,cellRowCount: 1,originalX: PTAppBaseConfig.share.defaultViewSpace,cellTrailingSpace: CGFloat.GlobalItemSpacing)
        }
        view.cellInCollection = { collectionView,sectionModel,indexPath in
            if let itemRow = sectionModel.rows?[indexPath.row] {
                let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
                if let cell = getCell as? PTTripDataCell {
                    cell.cellModel = PTTripManager.shared.tripHistory[indexPath.row]
                    cell.backgroundColor = .white.withAlphaComponent(0.1)
                    return cell
                }
            }
            return nil
        }
        return view
    }()

    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        
        let collectionInset:CGFloat = CGFloat.kTabbarHeight_Total
        detailCollection.contentCollectionView.contentInsetAdjustmentBehavior = .never
        detailCollection.contentCollectionView.contentInset.bottom = collectionInset
        detailCollection.contentCollectionView.verticalScrollIndicatorInsets.bottom = collectionInset

        view.addSubviews([detailCollection])
        detailCollection.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
        PTNSLogConsole(">>>>>>>>>>>>\(PTTripManager.shared.tripHistory)")
        listSet()
    }
    
    func listSet(finishTask:PTCollectionCallback? = nil) {
        var sections = [PTSection]()
        let rowsTrip = PTTripManager.shared.tripHistory.map { value in
            let row = PTRows(ID:PTTripDataCell.ID)
            return row
        }
        let sectionTrip = PTSection(rows: rowsTrip)
        sections.append(sectionTrip)
        detailCollection.showCollectionDetail(collectionData: sections,finishTask: finishTask)
    }

}
