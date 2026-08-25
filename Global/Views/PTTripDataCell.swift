//
//  PTTripDataCell.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 24/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit
import SwiftDate
import AttributedString
import AMapNaviKit
import SafeSFSymbols

class PTTripDataCell: PTBaseSwipeCell {
    static let ID = "PTTripDataCell"
    
    static let ChartHeight: CGFloat = 160
    static let MapHeight: CGFloat = 140
    
    // MARK: - 🪝 事件回调 (Closures) 彻底解耦
    /// 点击 GPX 导出按钮的回调 (传出 fileName 和触发的 View 供 iPad 气泡使用)
    var gpxExportAction: ((String, UIView) -> Void)?
    /// 图片彻底丢失，请求外部（ViewController）触发后台地图重绘机制
    var requestMapSnapshotAction: ((String) -> Void)?
    var trashAction: PTActionTask?
    var mapImageTapAction: PTActionTask?

    // MARK: - 📦 UI 组件
    
    // 标题时间
    lazy var timeTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .appfont(size: 15,bold: true)
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    private lazy var reviewSummaryLabel: UILabel = {
        let label = UILabel()
        label.font = .appfont(size: 10, bold: true)
        label.textColor = .systemOrange
        label.adjustsFontSizeToFitWidth = true
        return label
    }()
    
    // 现代化数据网格容器
    private lazy var statsGridStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.distribution = .fillEqually
        return stack
    }()
    
    // 地图缩略图
    lazy var thumbnailImageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        view.backgroundColor = UIColor(white: 0.15, alpha: 1.0) // 默认占位底色
        view.isUserInteractionEnabled = true
        
        let tap = UITapGestureRecognizer { sender in
            self.mapImageTapAction?()
        }
        view.addGestureRecognizer(tap)
        return view
    }()
    
    lazy var gpxButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.square.andArrowUp).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.addActionHandlers { [weak self] sender in
            guard let self = self, let gpx = self.cellModel?.gpxFileName else {
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "alert_title"))
                return
            }
            self.gpxExportAction?(gpx, sender)
        }
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        return view
    }()
    
    lazy var trashButton: PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.trash).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.addActionHandlers { [weak self] sender in
            self?.trashAction?()
        }
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        return view
    }()
    
    // 横向分页滑动的图表容器
    private lazy var chartsScrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = true
        scroll.clipsToBounds = false
        return scroll
    }()
    
    private lazy var chartsHStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 0 // 保证分页对齐
        stack.distribution = .fillEqually
        return stack
    }()
    
    // 图表实例
    lazy var speedChart = PTNativeTelemetryChartView()
    lazy var rpmChart = PTNativeTelemetryChartView()
    lazy var leanAngleChart = PTNativeTelemetryChartView()
    lazy var gChart = PTNativeTelemetryChartView()
    lazy var pChart = PTNativeTelemetryChartView()
    lazy var altitudeChart = PTNativeTelemetryChartView()
    lazy var pressureChart = PTNativeTelemetryChartView()
    lazy var slipRatioChart = PTNativeTelemetryChartView()
    
    // MARK: - 🔄 数据绑定
    var cellModel: PTTripReport! {
        didSet {
            bindData()
        }
    }
    
    // MARK: - 🛠 初始化与布局
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        contentContainer.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        contentContainer.layer.cornerRadius = 16 // 现代化大圆角
        contentContainer.clipsToBounds = true
        
        contentContainer.addSubviews([
            timeTitleLabel,
            reviewSummaryLabel,
            statsGridStackView,
            thumbnailImageView,
            gpxButton,
            trashButton,
            chartsScrollView
        ])
                
        // 组装横向滚动图表
        chartsScrollView.addSubview(chartsHStack)
        let allCharts = [speedChart, rpmChart, leanAngleChart, gChart, pChart, altitudeChart, pressureChart, slipRatioChart]
        allCharts.forEach { chartsHStack.addArrangedSubview($0) }
    }
    
    private func setupConstraints() {
        let margin: CGFloat = 16
        
        // 地图缩略图 (右上角)
        thumbnailImageView.snp.makeConstraints { make in
            make.top.right.equalToSuperview().inset(margin)
            make.size.equalTo(PTTripDataCell.MapHeight)
        }
        
        // 悬浮毛玻璃 GPX 按钮 (地图右下角，稍微内缩)
        gpxButton.snp.makeConstraints { make in
            make.right.bottom.equalTo(thumbnailImageView).inset(6)
            make.size.equalTo(32)
        }
        
        trashButton.snp.makeConstraints { make in
            make.right.top.equalTo(thumbnailImageView).inset(6)
            make.size.equalTo(gpxButton)
        }
        
        // 标题 (左上角)
        timeTitleLabel.snp.makeConstraints { make in
            make.top.left.equalToSuperview().inset(margin)
            make.right.equalTo(thumbnailImageView.snp.left).offset(-margin)
        }

        reviewSummaryLabel.snp.makeConstraints { make in
            make.top.equalTo(timeTitleLabel.snp.bottom).offset(4)
            make.left.right.equalTo(timeTitleLabel)
        }
        
        // 数据网格 (标题下方)
        statsGridStackView.snp.makeConstraints { make in
            make.top.equalTo(reviewSummaryLabel.snp.bottom).offset(8)
            make.left.equalToSuperview().inset(margin)
            make.right.equalTo(thumbnailImageView.snp.left).offset(-margin)
        }
        
        // 滑动图表区域 (下方)
        chartsScrollView.snp.makeConstraints { make in
            // 智能避让：在地图或统计数据的下方
            make.top.greaterThanOrEqualTo(statsGridStackView.snp.bottom).offset(margin)
            make.top.greaterThanOrEqualTo(thumbnailImageView.snp.bottom).offset(margin)
            make.left.right.bottom.equalToSuperview().inset(margin)
            make.height.equalTo(PTTripDataCell.ChartHeight)
        }
        
        // 图表内部约束 (核心：保证分页大小与 ScrollView 视口一致)
        chartsHStack.snp.makeConstraints { make in
            make.edges.equalTo(chartsScrollView.contentLayoutGuide)
            make.height.equalTo(chartsScrollView.frameLayoutGuide)
        }
        
        // 保证每个图表的宽度恰好等于 ScrollView 的宽度（实现完美 Paging）
        let allCharts = [speedChart, rpmChart, leanAngleChart, gChart, pChart, altitudeChart, pressureChart, slipRatioChart]
        allCharts.forEach { chart in
            chart.snp.makeConstraints { make in
                make.width.equalTo(chartsScrollView.frameLayoutGuide.snp.width)
            }
        }
    }
    
    // MARK: - 🧠 数据绑定与更新逻辑
    private func bindData() {
        // 时间标题
        let startTime = cellModel.startTime.convertTo(region: .local).toFormat("MM-dd HH:mm")
        let endTime = cellModel.endTime.convertTo(region: .local).toFormat("HH:mm")
        timeTitleLabel.text = "🏁 \(startTime) -> \(endTime)"
        let reviewTitles = cellModel.reviewEvents.prefix(3).map { $0.type.title }
        reviewSummaryLabel.text = reviewTitles.isEmpty
            ? "复盘：暂无明显事件"
            : "复盘：" + reviewTitles.joined(separator: " · ")
        
        // 更新数据网格
        updateStatsGrid()
        
        // 绑定图表数据
        bindChartData()
        
        // 处理地图图片 (极致的防御性加载)
        loadThumbnailImage()
    }
    
    // 🚀 构建现代化网格 UI
    private func updateStatsGrid() {
        // 清理旧视图
        statsGridStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // 第一行：里程 & 极速
        let row1 = UIStackView(arrangedSubviews: [
            createStatItem(icon: UIImage(.road.lanes), value: PTDashboardConfig.shared.appShowMileageValueString(cellModel.distanceKm), unit: PTDashboardConfig.shared.appShowUniLabel),
            createStatItem(icon: UIImage(.gauge.withDotsNeedle_100percent), value: PTDashboardConfig.shared.appShowMileageValueString(cellModel.maxSpeedKmh), unit: PTDashboardConfig.shared.appShowUniLabel + "/h")
        ])
        row1.axis = .horizontal
        row1.distribution = .fillEqually
        
        // 第二行：均速 & 最大转速
        let row2 = UIStackView(arrangedSubviews: [
            createStatItem(icon: UIImage(.gauge.withDotsNeedle_50percent), value: PTDashboardConfig.shared.appShowMileageValueString(cellModel.gpsAvgSpeedKmh), unit: PTDashboardConfig.shared.appShowUniLabel + "/h"),
            createStatItem(icon: UIImage(.arrow.counterclockwiseCircle), value: "\(cellModel.maxRpm)", unit: "rpm")
        ])
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        
        // 第三行：油耗
        let row3 = UIStackView(arrangedSubviews: [
            createStatItem(icon: UIImage(.fuelpump), value: String(format: "%.1f", cellModel.avgConsumption), unit: "L/100" + PTDashboardConfig.shared.appShowUniLabel),
            UIView() // 占位空 View，保持网格对齐
        ])
        row3.axis = .horizontal
        row3.distribution = .fillEqually
        
        statsGridStackView.addArrangedSubview(row1)
        statsGridStackView.addArrangedSubview(row2)
        statsGridStackView.addArrangedSubview(row3)
    }
    
    // 构建单个数据块：[图标 值] \n [单位]
    private func createStatItem(icon: UIImage, value: String, unit: String) -> UIView {
        let container = UIView()
        
        let iconView = UIImageView(image: icon.withTintColor(.lightGray, renderingMode: .alwaysOriginal))
        iconView.contentMode = .scaleAspectFit
        
        let valLabel = UILabel()
        valLabel.text = value
        valLabel.font = .appfont(size: 16,bold: true)
        valLabel.textColor = .white
        
        let unitLabel = UILabel()
        unitLabel.text = unit
        unitLabel.font = .appfont(size: 11,bold: true)
        unitLabel.textColor = .lightGray
        
        container.addSubviews([iconView, valLabel, unitLabel])
        
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalTo(valLabel)
            make.size.equalTo(14)
        }
        valLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(4)
            make.top.equalToSuperview()
            make.right.lessThanOrEqualToSuperview()
        }
        unitLabel.snp.makeConstraints { make in
            make.left.equalTo(valLabel)
            make.top.equalTo(valLabel.snp.bottom).offset(2)
            make.bottom.equalToSuperview()
        }
        
        return container
    }
    
    private func bindChartData() {
        speedChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "Speed"), color: .systemRed, data: cellModel.speedTrace)])
        rpmChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "RPM"), color: .systemGreen, data: cellModel.rpmTrace.map { Double($0) })])
        leanAngleChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "lean_angle_title"), color: .systemRed, data: cellModel.leanAngleTrace)])
        gChart.bindData(lines: [
            PTChartLineModel(name: "G:X", color: .systemRed, data: cellModel.gForceXTrace),
            PTChartLineModel(name: "G:Y", color: .systemGreen, data: cellModel.gForceYTrace),
            PTChartLineModel(name: "G:Z", color: .systemBlue, data: cellModel.gForceZTrace)
        ])
        pChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "vechicle_pitch"), color: .systemRed, data: cellModel.pitchTrace)])
        altitudeChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "elevation_title"), color: .systemRed, data: cellModel.relativeAltitudeTrace)])
        pressureChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "hpa_title"), color: .systemRed, data: cellModel.pressureTrace)])
        slipRatioChart.bindData(lines: [PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "Slip Ratio"), color: .systemRed, data: cellModel.slipRatioTrace)])
    }
    
    private func loadThumbnailImage() {
        guard let gpxName = cellModel.gpxFileName else { return }
        let imageName = gpxName.replacingOccurrences(of: ".gpx", with: ".jpg")
        
        // 清楚复用时的老图，防止闪烁
        thumbnailImageView.image = nil
        
        PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: imageName) { [weak self] localImageURL in
            guard let self = self else { return }
            
            if let imgURL = localImageURL, FileManager.default.fileExists(atPath: imgURL.path) {
                // 成功找到图片
                DispatchQueue.main.async {
                    self.thumbnailImageView.image = UIImage(contentsOfFile: imgURL.path)
                }
            } else {
                // 图片丢失，通知外部去后台生成，坚决不能在 Cell 里面生成避免卡死主线程
                DispatchQueue.main.async {
                    self.requestMapSnapshotAction?(gpxName)
                }
            }
        }
    }
}

@objcMembers
public class PTRouteSnapshotManager: NSObject, MAMapViewDelegate {
    
    public static let shared = PTRouteSnapshotManager()
    
    // 保持对离屏地图的强引用，防止在异步截图完成前被释放
    private var tempMapView: MAMapView?
    
    /// 根据坐标点生成一张地图缩略图，并自动保存到沙盒
    /// - Parameters:
    ///   - points: 骑行坐标点数组
    ///   - gpxFileName: 关联的 GPX 文件名 (用于生成同名的 .jpg)
    public func generateAndSaveSnapshot(coordinates: [CLLocationCoordinate2D], gpxFileName: String, reviewEvents: [PTRideReviewEvent] = [], completion: ((URL?) -> Void)? = nil) {
            
        guard coordinates.count > 1 else {
            completion?(nil)
            return
        }
        
        // 🚨 必须在主线程创建和操作地图 UI
        DispatchQueue.main.async {
            let mapView = MAMapView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            mapView.delegate = self
            mapView.isZoomEnabled = false
            mapView.isScrollEnabled = false
            mapView.showsCompass = false
            mapView.showsScale = false
            
            self.tempMapView = mapView
            
            var coords = coordinates
            if let polyline = MAPolyline(coordinates: &coords, count: UInt(coords.count)) {
                mapView.add(polyline)
                let padding = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30)
                mapView.setVisibleMapRect(polyline.boundingMapRect, edgePadding: padding, animated: false)
            }

            // 中文：把复盘事件叠加到路线快照；Español: superponer los eventos de revisión en la instantánea.
            let annotations = reviewEvents.map { event -> MAPointAnnotation in
                let annotation = MAPointAnnotation()
                annotation.coordinate = CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude)
                annotation.title = "PTReview:\(event.type.rawValue)"
                return annotation
            }
            if !annotations.isEmpty {
                mapView.addAnnotations(annotations)
            }
            
            // 延迟等待底图加载完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                mapView.takeSnapshot(in: mapView.bounds) { [weak self = self] (image, state) in
                    var resultURL: URL? = nil
                    
                    if let img = image, let data = img.jpegData(compressionQuality: 0.8) {
                        let imageFileName = gpxFileName.replacingOccurrences(of: ".gpx", with: ".jpg")
                        
                        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let fileURL = docsDir.appendingPathComponent(imageFileName)
                            do {
                                // 存入本地沙盒
                                try data.write(to: fileURL)
                                PTNSLogConsole("📸 [地图补救机制] 缩略图重绘成功: \(imageFileName)")
                                
                                // 🚨 立刻备份到 iCloud，补齐云端缺失的文件！
                                PTiCloudFileManager.shared.backupDatabaseToICloud(dbName: imageFileName)
                                
                                resultURL = fileURL
                            } catch {
                                PTNSLogConsole("❌ [地图快照] 保存失败: \(error)")
                            }
                        }
                    }
                    
                    self?.tempMapView = nil
                    // 回调通知 UI 更新
                    completion?(resultURL)
                }
            }
        }
    }

    // MARK: - MAMapViewDelegate
    public func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
        if let polyline = overlay as? MAPolyline {
            let renderer = MAPolylineRenderer(polyline: polyline)
            renderer?.lineWidth = 6.0
            renderer?.strokeColor = PTDashboardConfig.shared.appMainColor
            return renderer
        }
        return nil
    }

    public func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
        guard let title = annotation.title, title?.hasPrefix("PTReview:") == true else { return nil }

        let identifier = "PTRideReviewAnnotation"
        guard let view = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MAPinAnnotationView)
            ?? MAPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        else { return nil }
        view.annotation = annotation
        view.pinColor = .purple
        view.animatesDrop = false
        view.canShowCallout = false
        return view
    }
}
