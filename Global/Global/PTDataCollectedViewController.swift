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
import SafeSFSymbols

class PTDataCollectedViewController: PTMotoBaseViewController {

    lazy var appLogo:UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "app_inside_logo")
        view.bounds = .init(origin: .zero, size: .init(width: 108.adapter, height: PTAppBaseConfig.share.navBarButtonSize))
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }()
        
    var listEmptyConfig:PTEmptyDataViewConfig!
    lazy var detailCollection:PTCollectionView = {
        let collectionConfig = PTDashboardConfig.baseCollectionConfig(emptyConfig:self.listEmptyConfig)
        collectionConfig.viewType = .Custom
        collectionConfig.footerRefresh = false
        collectionConfig.topRefresh = false

        let view = PTCollectionView(viewConfig: collectionConfig)
        view.registerClassCells(classs: [PTTripDataCell.ID:PTTripDataCell.self])
        view.customerLayout = { sectionIndex,section in
            let itemHeight:CGFloat = PTTripDataCell.lineMaxHeight * PTTripDataCell.lineCount + (PTTripDataCell.lineCount - 1) * PTTripDataCell.textLineSpacing + PTTripDataCell.ChartHeight * 8 + CGFloat.GlobalItemSpacing * 11
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: itemHeight,cellRowCount: 1,originalX: PTAppBaseConfig.share.defaultViewSpace,cellTrailingSpace: CGFloat.GlobalItemSpacing)
        }
        view.indexPathSwipe = { sModel,indexPath in
            return true
        }
        view.swipeRightHandler = { collectionView,sectionModel,indexPath in
            let deleteAction = PTSwipeAction(name: PTDashboardConfig.languageFunc(text: "Delete"),image: nil, nameColor:.white,nameFont:.appfont(size: 14), backgroundColor: .systemRed) { sender in
                UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "Delete") + "?",okBtns: [PTDashboardConfig.languageFunc(text: "button_confirm")],cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), moreBtn:  { index, title in
                    let ready = PTTripManager.shared.tripHistory[indexPath.row]
                    if let findIndex = PTTripManager.shared.tripHistory.firstIndex(where: { $0.startTime == ready.startTime }),let findRow = self.detailCollection.getRow(at: indexPath) {
                        self.detailCollection.deleteRows([findRow], from: 0)
                        PTTripManager.shared.deleteTrip(ready)
                    }
                })
            }
            return [deleteAction]
        }
        view.cellInCollection = { collectionView,sectionModel,indexPath in
            if let itemRow = sectionModel.rows?[indexPath.row] {
                let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
                if let cell = getCell as? PTTripDataCell {
                    cell.cellModel = PTTripManager.shared.tripHistory[indexPath.row]
                    return cell
                }
            }
            return nil
        }
        return view
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        
        setEmptyConfig(empty: .Normal)
        let collectionInset:CGFloat = CGFloat.kTabbarHeight_Total
        detailCollection.contentCollectionView.contentInsetAdjustmentBehavior = .never
        detailCollection.contentCollectionView.contentInset.bottom = collectionInset
        detailCollection.contentCollectionView.verticalScrollIndicatorInsets.bottom = collectionInset

        view.addSubviews([detailCollection])
        detailCollection.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
        }
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

    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        detailCollection.clearAllData { _ in
            self.listSet()
        }
    }
    
    func setEmptyConfig(empty:PTCollectionEmptyType) {
        self.listEmptyConfig = PTDashboardConfig.setEmptyConfig(empty: empty) {
            PTGCDManager.shared.runOnMain {
                self.listSet()
            }
        }
        detailCollection.viewConfig.emptyViewConfig = self.listEmptyConfig
        detailCollection.reloadEmptyConfig()
    }
}
