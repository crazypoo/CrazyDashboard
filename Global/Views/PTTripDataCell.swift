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

class PTTripDataCell: PTBaseNormalCell {
    static let ID = "PTTripDataCell"
    
    static let ChartHeight:CGFloat = 150
    static let MapHeight:CGFloat = 88

    var cellModel:PTTripReport! {
        didSet {
            let startTime = cellModel.startTime.convertTo(region: .local).toFormat("yyyy-MM-dd HH:mm:ss")
            let endTime = cellModel.endTime.convertTo(region: .local).toFormat("yyyy-MM-dd HH:mm:ss")
            let distanceString = PTDashboardConfig.languageFunc(text: "casa_card_little_trip") + ":" + String(format: "%@%@", PTDashboardConfig.shared.appShowMileageValueString(cellModel.distanceKm),PTDashboardConfig.shared.appShowUniLabel)
            let speedRpm = "Max speed:" + String(format: "%@%@", PTDashboardConfig.shared.appShowMileageValueString(cellModel.maxSpeedKmh),PTDashboardConfig.shared.appShowUniLabel) + ",Max Rpm:" + "\(cellModel.maxRpm)"
            let avgOil = PTDashboardConfig.languageFunc(text: "casa_card_avg_oil") + ":\(cellModel.avgConsumption)"
            let nameAtt: ASAttributedString = """
                        \(wrap: .embedding("""
                        \((startTime + " -> " + endTime),.foreground(.white),.font(.appfont(size: 14)))
                        \(distanceString,.foreground(.white),.font(.appfont(size: 14)))
                        \(speedRpm,.foreground(.white),.font(.appfont(size: 14)))
                        \(avgOil,.foreground(.white),.font(.appfont(size: 14)))
                        """),.paragraph(.alignment(.left)))
                        """
            timeLabel.attributed.text = nameAtt
            
            let chartModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "倾角"), color: .systemRed, data: cellModel.leanAngleTrace)
            leanAngleChart.bindData(lines: [chartModel])
            
            let gXModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "G:X"), color: .systemRed, data: cellModel.gForceXTrace)
            let gYModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "G:Y"), color: .systemGreen, data: cellModel.gForceYTrace)
            let gZModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "G:Z"), color: .systemBlue, data: cellModel.gForceZTrace)

            gChart.bindData(lines: [gXModel,gYModel,gZModel])
            
            let pModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "P"), color: .systemRed, data: cellModel.pitchTrace)
            pChart.bindData(lines: [pModel])
            
            let aModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "海拔"), color: .systemRed, data: cellModel.relativeAltitudeTrace)
            altitudeChart.bindData(lines: [aModel])
            
            let pressureModel = PTChartLineModel(name: PTDashboardConfig.languageFunc(text: "气压"), color: .systemRed, data: cellModel.pressureTrace)
            pressureChart.bindData(lines: [pressureModel])
            
            guard let gpxName = cellModel.gpxFileName else { return }
            let imageName = gpxName.replacingOccurrences(of: ".gpx", with: ".jpg")
            
            // 步骤 1：尝试去本地或 iCloud 找图片
            PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: imageName) { [weak self] localImageURL in
                guard let self = self else { return }
                
                if let imgURL = localImageURL, FileManager.default.fileExists(atPath: imgURL.path) {
                    // 🎉 太棒了！找到了图片，直接显示
                    self.thumbnailImageView.loadImage(contentData: UIImage(contentsOfFile: imgURL.path) as Any)
                } else {
                    
                    // 🚨 步骤 2：图片彻底丢失！触发【亡羊补牢】重绘机制！
                    PTNSLogConsole("⚠️ 未找到缩略图，启动根据原始 GPX 重绘机制...")
                    
                    // 请求下载并获取原始的 GPX 数据文件
                    PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: gpxName) { localGpxURL in
                        guard let gpxURL = localGpxURL else {
                            PTNSLogConsole("❌ 原始 GPX 文件也丢失了，无法重绘。")
                            return
                        }
                        
                        // a) 解析 GPX 文件，提取坐标
                        let parser = PTGPXParser()
                        let coordinates = parser.parse(fileURL: gpxURL)
                        
                        // b) 调用快照生成器，当场重绘、上传 iCloud 并拿到新图片
                        PTRouteSnapshotManager.shared.generateAndSaveSnapshot(coordinates: coordinates, gpxFileName: gpxName) { newImageURL in
                            if let newURL = newImageURL {
                                // c) 在主线程将新鲜出炉的图片更新到界面上
                                DispatchQueue.main.async {
                                    self.thumbnailImageView.loadImage(contentData: UIImage(contentsOfFile: newURL.path) as Any)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    lazy var timeLabel:UILabel = {
        let view = UILabel()
        view.numberOfLines = 0
        return view
    }()
    
    lazy var leanAngleChart:PTNativeTelemetryChartView = {
        let view = PTNativeTelemetryChartView()
        return view
    }()

    lazy var gChart:PTNativeTelemetryChartView = {
        let view = PTNativeTelemetryChartView()
        return view
    }()
    
    lazy var pChart:PTNativeTelemetryChartView = {
        let view = PTNativeTelemetryChartView()
        return view
    }()
    
    lazy var altitudeChart:PTNativeTelemetryChartView = {
        let view = PTNativeTelemetryChartView()
        return view
    }()
    
    lazy var pressureChart:PTNativeTelemetryChartView = {
        let view = PTNativeTelemetryChartView()
        return view
    }()
    
    lazy var thumbnailImageView:UIButton = {
        let view = UIButton(type:.custom)
        view.imageView?.contentMode = .scaleAspectFit
        view.imageView?.clipsToBounds = false
        return view
    }()
    
    lazy var gpxButton:UIButton = {
        let view = UIButton(type: .custom)
        view.setImage(UIImage(.dot.scope), for: .normal)
        view.addActionHandlers { sender in
            if let gpx = self.cellModel.gpxFileName {
                PTiCloudFileManager.shared.fetchCloudFileIfNeeded(fileName: gpx) { localImageURL in
                    if let url = localImageURL {
                        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        
                        // 查找最顶层控制器以执行 Present 操作
                        if let topVC = PTUtils.getCurrentVC() {
                            // 兼容 iPad，防止崩溃（指定气泡弹出的源头）
                            if let popover = activityVC.popoverPresentationController {
                                popover.sourceView = sender
                                popover.sourceRect = sender.bounds
                            }
                            
                            topVC.present(activityVC, animated: true, completion: nil)
                        }
                    }
                }
            } else {
                PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "alert_title"))
            }
        }
        return view
    }()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        contentView.addSubviews([timeLabel,leanAngleChart,gChart,pChart,altitudeChart,pressureChart,thumbnailImageView,gpxButton])
        timeLabel.snp.makeConstraints { make in
            make.left.top.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        
        leanAngleChart.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
            make.top.equalTo(self.timeLabel.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.height.equalTo(PTTripDataCell.ChartHeight)
        }
        
        gChart.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.leanAngleChart)
            make.top.equalTo(self.leanAngleChart.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        pChart.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.leanAngleChart)
            make.top.equalTo(self.gChart.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        altitudeChart.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.leanAngleChart)
            make.top.equalTo(self.pChart.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        pressureChart.snp.makeConstraints { make in
            make.left.right.height.equalTo(self.leanAngleChart)
            make.top.equalTo(self.altitudeChart.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        thumbnailImageView.snp.makeConstraints { make in
            make.size.equalTo(PTTripDataCell.MapHeight)
            make.top.equalTo(self.pressureChart.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
        }
        thumbnailImageView.layoutIfNeeded()
        thumbnailImageView.viewCorner(radius: 4)
        
        gpxButton.snp.makeConstraints { make in
            make.size.equalTo(44)
            make.bottom.equalTo(self.thumbnailImageView)
            make.right.equalTo(self.thumbnailImageView.snp.left).offset(-CGFloat.GlobalItemSpacing)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
    public func generateAndSaveSnapshot(coordinates: [CLLocationCoordinate2D], gpxFileName: String, completion: ((URL?) -> Void)? = nil) {
            
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
            
            // 延迟等待底图加载完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                mapView.takeSnapshot(in: mapView.bounds) { [weak self] (image, state) in
                    var resultURL: URL? = nil
                    
                    if let img = image, let data = img.jpegData(compressionQuality: 0.8) {
                        let imageFileName = gpxFileName.replacingOccurrences(of: ".gpx", with: ".jpg")
                        
                        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let fileURL = docsDir.appendingPathComponent(imageFileName)
                            do {
                                // 1. 存入本地沙盒
                                try data.write(to: fileURL)
                                PTNSLogConsole("📸 [地图补救机制] 缩略图重绘成功: \(imageFileName)")
                                
                                // 2. 🚨 立刻备份到 iCloud，补齐云端缺失的文件！
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
}
