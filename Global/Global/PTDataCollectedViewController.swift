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
            let itemHeight:CGFloat = 380//PTTripDataCell.lineMaxHeight * PTTripDataCell.lineCount + (PTTripDataCell.lineCount - 1) * PTTripDataCell.textLineSpacing + PTTripDataCell.ChartHeight * 8 + CGFloat.GlobalItemSpacing * 11
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: itemHeight,cellRowCount: 1,originalX: PTAppBaseConfig.share.defaultViewSpace,cellTrailingSpace: CGFloat.GlobalItemSpacing)
        }
        view.indexPathSwipe = { sModel,indexPath in
            return false
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
                    cell.trashAction = {
                        PTGCDManager.shared.runOnMain {
                            UIAlertController.base_alertVC(title: PTDashboardConfig.languageFunc(text: "Delete") + "?",okBtns: [PTDashboardConfig.languageFunc(text: "button_confirm")],cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"), moreBtn:  { index, title in
                                let ready = PTTripManager.shared.tripHistory[indexPath.row]
                                if let findIndex = PTTripManager.shared.tripHistory.firstIndex(where: { $0.startTime == ready.startTime }),let findRow = self.detailCollection.getRow(at: indexPath) {
                                    self.detailCollection.deleteRows([findRow], from: 0)
                                    PTTripManager.shared.deleteTrip(ready)
                                }
                            })
                        }
                    }
                    // 处理 GPX 导出交互
                    cell.gpxExportAction = { [weak self = self] (gpxFileName, senderView) in
                        guard let self = self else { return }
                        PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: gpxFileName) { localURL in
                            if let url = localURL {
                                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                if let popover = activityVC.popoverPresentationController {
                                    popover.sourceView = senderView
                                    popover.sourceRect = senderView.bounds
                                }
                                self.present(activityVC, animated: true, completion: nil)
                            }
                        }
                    }
                    
                    // 处理地图图片丢失时的静默重绘 (非常关键)
                    cell.requestMapSnapshotAction = { [weak self = self] gpxFileName in
                        // 建议在这里判断一下是否已经在生成中，避免重复触发
                        PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: gpxFileName) { localGpxURL in
                            guard let gpxURL = localGpxURL else { return }
                            let coordinates = PTGPXParser().parse(fileURL: gpxURL)
                            PTRouteSnapshotManager.shared.generateAndSaveSnapshot(coordinates: coordinates, gpxFileName: gpxFileName) { newURL in
                                // 生成成功后，只刷新当前行即可
                                DispatchQueue.main.async {
                                    if let rows = self?.detailCollection.getRows(at: [indexPath]) {
                                        self?.detailCollection.reloadRows(rows, in: indexPath.section)
                                    }
                                }
                            }
                        }
                    }
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
