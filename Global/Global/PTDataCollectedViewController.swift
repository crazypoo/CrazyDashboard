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
import SwiftDate

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
    private var snapshotRequestsInFlight = Set<String>()
    lazy var detailCollection:PTCollectionView = {
        let collectionConfig = PTDashboardConfig.baseCollectionConfig(emptyConfig:self.listEmptyConfig)
        collectionConfig.viewType = .Custom
        collectionConfig.footerRefresh = false
        collectionConfig.topRefresh = false

        let view = PTCollectionView(viewConfig: collectionConfig)
        view.registerClassCells(classs: [PTTripDataCell.ID:PTTripDataCell.self])
        view.customerLayout = { sectionIndex,section in
            let itemHeight:CGFloat = 220
            return UICollectionView.girdCollectionLayout(data: section.rows, itemHeight: itemHeight,cellRowCount: 1,originalX: PTAppBaseConfig.share.defaultViewSpace,cellTrailingSpace: CGFloat.GlobalItemSpacing)
        }
        view.indexPathSwipe = { sModel,indexPath in
            return false
        }
        view.swipeRightHandler = { [weak self] collectionView,sectionModel,indexPath in
            let deleteAction = PTSwipeAction(name: PTDashboardConfig.languageFunc(text: "Delete"),image: nil, nameColor:.white,nameFont:.appfont(size: 14), backgroundColor: .systemRed) { sender in
                self?.requestDeleteTrip(at: indexPath)
            }
            return [deleteAction]
        }
        view.cellInCollection = { [weak self] collectionView, sectionModel, indexPath in
            guard let owner = self,
                  let itemRow = sectionModel.rows?[indexPath.row],
                  PTTripManager.shared.tripHistory.indices.contains(indexPath.row) else {
                return nil
            }
            let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
            guard let cell = getCell as? PTTripDataCell else { return nil }

            let report = PTTripManager.shared.tripHistory[indexPath.row]
            cell.cellModel = report
            cell.trashAction = { [weak owner] in
                Task { @MainActor [weak owner] in
                    owner?.requestDeleteTrip(at: indexPath)
                }
            }

            // 处理 GPX 导出交互
            cell.gpxExportAction = { [weak owner] (gpxFileName, senderView) in
                PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: gpxFileName) { localURL in
                    if let url = localURL {
                        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = senderView
                            popover.sourceRect = senderView.bounds
                        }
                        owner?.present(activityVC, animated: true, completion: nil)
                    }
                }
            }

            // 处理地图图片丢失时的静默重绘 (非常关键)
            cell.requestMapSnapshotAction = { [weak owner] gpxFileName in
                guard let owner,
                      owner.snapshotRequestsInFlight.insert(gpxFileName).inserted else {
                    return
                }

                PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: gpxFileName) { localGpxURL in
                    guard let localGpxURL else {
                        owner.snapshotRequestsInFlight.remove(gpxFileName)
                        return
                    }

                    // EN: Parse the route away from the main thread before creating the map snapshot.
                    // ES: Analizamos la ruta fuera del hilo principal antes de crear la instantánea del mapa.
                    // 中文：先在后台解析轨迹，再回主线程创建地图快照。
                    DispatchQueue.global(qos: .utility).async {
                        let coordinates = PTGPXParser().parse(fileURL: localGpxURL)
                        DispatchQueue.main.async {
                            PTRouteSnapshotManager.shared.generateAndSaveSnapshot(coordinates: coordinates, gpxFileName: gpxFileName) { newURL in
                                owner.snapshotRequestsInFlight.remove(gpxFileName)
                                guard newURL != nil,
                                      let currentIndex = PTTripManager.shared.tripHistory.firstIndex(where: { $0.gpxFileName == gpxFileName }) else {
                                    return
                                }

                                let currentIndexPath = IndexPath(row: currentIndex, section: 0)
                                let rows = owner.detailCollection.getRows(at: [currentIndexPath])
                                if !rows.isEmpty {
                                    owner.detailCollection.reloadRows(rows, in: currentIndexPath.section)
                                }
                            }
                        }
                    }
                }
            }

            // EN: Open the synchronized offline replay when the route thumbnail is tapped.
            // ES: Abre la reproducción offline sincronizada al tocar la miniatura de la ruta.
            // 中文：点击路线缩略图时打开同步的离线回放页面。
            cell.mapImageTapAction = { [weak owner, report] in
                guard let owner else { return }
                Task { @MainActor in
                    owner.presentReplay(for: report)
                }
            }
            return cell
        }
        // EN: Open the stable report snapshot when the summary card is selected.
        // ES: Abre la instantánea estable del informe al seleccionar la tarjeta de resumen.
        // 中文：选中摘要卡片时打开稳定的行程报告快照。
        view.collectionDidSelect = { [weak self] _, _, indexPath in
            guard let self,
                  PTTripManager.shared.tripHistory.indices.contains(indexPath.row) else {
                return
            }
            let reports = PTTripManager.shared.tripHistory
            let report = reports[indexPath.row]
            let analysis = PTRideAnalysisViewController(report: report, comparisonPool: reports)
            self.navigationController?.pushViewController(analysis, animated: true)
        }
        return view
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setLeftButtons(views: [appLogo])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // EN: Reload once asynchronous history restoration finishes.
        // ES: Recarga la lista cuando termina la restauración asíncrona del historial.
        // 中文：异步历史恢复完成后刷新列表。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTripHistoryLoaded),
            name: MotorcycleTripHistoryLoaded,
            object: nil
        )

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

    @objc private func handleTripHistoryLoaded() {
        guard isViewLoaded else { return }
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

    // EN: Confirm deletion by stable report ID so equal timestamps and reused index paths cannot remove the wrong ride.
    // ES: Confirma el borrado mediante el ID estable para que fechas iguales y celdas reutilizadas no eliminen otra ruta.
    // 中文：使用稳定报告 ID 确认删除，避免相同时间戳或复用索引误删其他骑行记录。
    private func requestDeleteTrip(at indexPath: IndexPath) {
        guard PTTripManager.shared.tripHistory.indices.contains(indexPath.row) else { return }
        let reportID = PTTripManager.shared.tripHistory[indexPath.row].id
        UIAlertController.base_alertVC(
            title: PTDashboardConfig.languageFunc(text: "Delete") + "?",
            okBtns: [PTDashboardConfig.languageFunc(text: "button_confirm")],
            cancelBtn: PTDashboardConfig.languageFunc(text: "button_cancel"),
            moreBtn: { [weak self] _, _ in
                guard let self,
                      let currentIndex = PTTripManager.shared.tripHistory.firstIndex(where: { $0.id == reportID }) else {
                    return
                }
                let currentIndexPath = IndexPath(row: currentIndex, section: indexPath.section)
                let row = self.detailCollection.getRow(at: currentIndexPath)
                guard let report = PTTripManager.shared.tripHistory.first(where: { $0.id == reportID }) else {
                    return
                }
                PTTripManager.shared.deleteTrip(report)
                if let row {
                    self.detailCollection.deleteRows([row], from: currentIndexPath.section)
                }
            }
        )
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

    // EN: Present replay as a separate read-only screen so history deletion stays unchanged.
    // ES: Presenta la reproducción en una pantalla de solo lectura para no alterar el borrado del historial.
    // 中文：以独立只读页面展示回放，不改变现有历史删除流程。
    private func presentReplay(for report: PTTripReport) {
        let replayViewController = PTRideReplayViewController(report: report)
        let navigationController = PTBaseNavControl(rootViewController: replayViewController)
        present(navigationController, animated: true)
    }
}
