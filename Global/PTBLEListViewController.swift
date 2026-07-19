//
//  PTBLEListViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit
import CoreBluetooth

class PTBLEListViewController: PTBaseViewController {

    let bleManager = PTBluetoothManager()
    
    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    lazy var detailCollection:PTCollectionView = {
                                
        let collectionConfig = PTCollectionViewConfig()
        collectionConfig.viewType = .Custom
        collectionConfig.footerRefresh = false
        collectionConfig.topRefresh = false

        let view = PTCollectionView(viewConfig: collectionConfig)
        view.registerClassCells(classs: [PTFusionCell.ID:PTFusionCell.self])
        view.customerLayout = { sectionIndex,section in
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: 44,cellRowCount: 1,originalX: PTAppBaseConfig.share.defaultViewSpace)
        }
        view.cellInCollection = { collectionView,sectionModel,indexPath in
            if let itemRow = sectionModel.rows?[indexPath.row] {
                let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
                if let cell = getCell as? PTFusionCell,let cellModel = itemRow.dataModel as? PTFusionCellModel {
                    cell.cellModel = cellModel
                    return cell
                }
            }
            return nil
        }
        view.collectionDidSelect = { collectionView,sectionModel,indexPath in
        }
        view.emptyTap = { emptyView in
//            self.viewTotalDataLoad()
        }
        return view
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let collectionInset:CGFloat = CGFloat.kTabbarHeight_Total
        detailCollection.contentCollectionView.contentInsetAdjustmentBehavior = .never
        detailCollection.contentCollectionView.contentInset.bottom = collectionInset
        detailCollection.contentCollectionView.verticalScrollIndicatorInsets.bottom = collectionInset

        view.addSubviews([detailCollection])
        detailCollection.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
        
        bleManager.onDeviceListUpdated = {
            self.detailCollection.clearAllData { _ in
                self.listSet()
            }
        }
    }
    
    func listSet(finishTask:PTCollectionCallback? = nil) {
        var sections = [PTSection]()
        let rows = bleManager.peripheralList.map { value in
            let rowModel = PTFusionCellModel()
            rowModel.name = value.name ?? "UNKNOWN"
            let row = PTRows(ID:PTFusionCell.ID,dataModel: rowModel)
            return row
        }
        let section = PTSection(rows: rows)
        sections.append(section)
        detailCollection.showCollectionDetail(collectionData: sections,finishTask: finishTask)
    }
}
