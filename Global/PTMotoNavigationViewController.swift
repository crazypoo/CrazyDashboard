//
//  PTMotoNavigationViewController.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 19/7/2026.
//

import UIKit
import PooTools
import SwifterSwift
import SnapKit
import CoreLocation
import MapKit
import AMapNaviKit
import AMapLocationKit
import AMapSearchKit
import CoreMotion

enum NaviPointAnnotationType: Int {
    case start
    case way
    case end
}

class NaviPointAnnotation: MAPointAnnotation {
    var naviPointType: NaviPointAnnotationType?
}

struct RouteCollectionViewInfo {
    var routeID: Int
    var title: String
    var subTitle: String
}

class SelectableOverlay: MABaseOverlay {
    var routeID: Int = 0
    var selected = false
    var selectedColor = UIColor(red: 0.05, green: 0.39, blue: 0.9, alpha: 0.8)
    var reguarColor = UIColor(red: 0.5, green: 0.6, blue: 0.9, alpha: 0.8)
    
    var overlay: MAOverlay
    
    init(aOverlay: MAOverlay) {
        overlay = aOverlay
        super.init()
    }
}

class PreferenceView: UIView {
    
    private var avoidCongestion: UIButton!
    private var avoidCost: UIButton!
    private var avoidHighway: UIButton!
    private var prioritiseHighway: UIButton!
    
    //MARK: Life Cycle
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        buildPreferenceView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    public func strategy(isMultiple: Bool) -> AMapNaviDrivingStrategy {
        return ConvertDrivingPreferenceToDrivingStrategy(isMultiple,
                                                         avoidCongestion.isSelected,
                                                         avoidHighway.isSelected,
                                                         avoidCost.isSelected,
                                                         prioritiseHighway.isSelected)
    }
    
    private func buildPreferenceView() {
        let singleWidth = (CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace * 2 - 50.0) / 4.0
        
        avoidCongestion = buttonForTitle("躲避拥堵")
        avoidCongestion.addTarget(self, action: #selector(self.avoidCongestionAction(sender:)), for: .touchUpInside)
        addSubview(avoidCongestion)
        avoidCongestion.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.equalToSuperview().inset(10)
            make.width.equalTo(singleWidth)
        }
        
        avoidCost = buttonForTitle("避免收费")
        avoidCost.addTarget(self, action: #selector(self.avoidCostAction(sender:)), for: .touchUpInside)
        addSubview(avoidCost)
        avoidCost.snp.makeConstraints { make in
            make.left.equalTo(self.avoidCongestion.snp.right).offset(10)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }
        
        avoidHighway = buttonForTitle("不走高速")
        avoidHighway.addTarget(self, action: #selector(self.avoidHighwayAction(sender:)), for: .touchUpInside)
        addSubview(avoidHighway)
        avoidHighway.snp.makeConstraints { make in
            make.left.equalTo(self.avoidCost.snp.right).offset(10)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }

        prioritiseHighway = buttonForTitle("高速优先")
        prioritiseHighway.addTarget(self, action: #selector(self.prioritiseHighwayAction(sender:)), for: .touchUpInside)
        addSubview(prioritiseHighway)
        prioritiseHighway.snp.makeConstraints { make in
            make.left.equalTo(self.avoidHighway.snp.right).offset(10)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }
    }
    
    @objc func avoidCongestionAction(sender: UIButton) {
        changeButtonState(sender, selected: !sender.isSelected)
    }
    
    @objc func avoidCostAction(sender: UIButton) {
        changeButtonState(sender, selected: !sender.isSelected)
        
        if sender.isSelected {
            changeButtonState(prioritiseHighway, selected: false)
        }
    }
    
    @objc func avoidHighwayAction(sender: UIButton) {
        changeButtonState(sender, selected: !sender.isSelected)
        
        if sender.isSelected {
            changeButtonState(prioritiseHighway, selected: false)
        }
    }
    
    @objc func prioritiseHighwayAction(sender: UIButton) {
        changeButtonState(sender, selected: !sender.isSelected)
        
        if sender.isSelected {
            changeButtonState(avoidCost, selected: false)
            changeButtonState(avoidHighway, selected: false)
        }
    }
    
    private func buttonForTitle(_ title: String) -> UIButton {
        let reBtn = UIButton(type: .custom)
        
        reBtn.layer.borderColor = UIColor.lightGray.cgColor
        reBtn.layer.borderWidth = 1.0
        reBtn.layer.cornerRadius = 5
        
        reBtn.bounds = CGRect(x: 0, y: 0, width: 80, height: 30)
        reBtn.setTitle(title, for: .normal)
        reBtn.setTitleColor(UIColor.black, for: .normal)
        reBtn.setTitleColor(UIColor.red, for: .selected)
        reBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        
        return reBtn
    }
    
    private func changeButtonState(_ button: UIButton, selected: Bool) {
        button.isSelected = selected
        button.layer.borderColor = button.isSelected ? UIColor.red.cgColor : UIColor.lightGray.cgColor
    }
}

class PTMotoNavigationViewController: PTBaseViewController,AMapNaviDriveDataRepresentable {

    var routeIndicatorInfoArray = [RouteCollectionViewInfo]()

//    lazy var tap:UIButton = {
//        let view = UIButton(type: .custom)
//        view.addActionHandlers { sender in
//            // 假设你要导航到某个坐标 (比如北京天安门)
//            let destinationCoordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
//
//            // 触发导航路线计算。一旦计算成功，它会自动在后台监听 GPS 并向摩托车发数据！
//            PTMapKitNavigationHelper.shared.startNavigation(to: destinationCoordinate)
//        }
//        view.backgroundColor = .systemBlue
//        return view
//    }()
    
    private lazy var amapView:MAMapView = {
        let view = MAMapView()
        view.delegate = self
        view.showsUserLocation = true
        view.userTrackingMode = .follow
        return view
    }()
    
    private lazy var locationManager:AMapLocationManager = {
        let manager = AMapLocationManager()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        return manager
    }()

    private lazy var search: AMapSearchAPI = {
        let view = AMapSearchAPI()
        view!.delegate = self
        return view!
    }()
    
    // MARK: - UI 组件
    private lazy var searchBar:PTSearchBar = {
        let view = PTSearchBar()
        view.searchPlaceholder = "搜索地址..."
        view.delegate = self
        view.searchBarStyle = .minimal
        view.backgroundColor = .white
        view.searchTextFieldBackgroundColor = .clear
        view.searchBarOutViewColor = .clear
        view.searchBarTextFieldBorderColor = .clear
        view.searchBarTextFieldCornerRadius = 0
        view.searchBarTextFieldBorderWidth = 0
        return view
    }()
    private lazy var searchResultsTableView:UITableView = {
        let view = UITableView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        view.dataSource = self
        view.isHidden = true // 默认隐藏
        view.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return view
    }()
    private let homeButton = UIButton(type: .system)
    private let officeButton = UIButton(type: .system)
    private lazy var startNavigationButton:UIButton = {
        let view = UIButton(type: .system)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setTitle("🚀 开始导航", for: .normal)
        view.titleLabel?.font = UIFont.boldSystemFont(ofSize: 18)
        view.backgroundColor = .systemGreen
        view.setTitleColor(.white, for: .normal)
        view.layer.cornerRadius = 12
        view.isHidden = true // 只有规划好路线才显示
        view.addActionHandlers(handler: { _ in
            self.startNavigationTapped()
            AMapNaviDriveManager.sharedInstance().startGPSNavi()
        })
        return view
    }()
        
    private var amapSearchResults:[MAPointAnnotation] = []
    
    // MARK: - 状态变量
    private var currentDestination: CLLocationCoordinate2D?
    private var currentRouteOverlay: MKPolyline?

    lazy var preferenceView: PreferenceView = {
        let view = PreferenceView()
        return view
    }()
    var isMultipleRoutePlan = true

    lazy var driveView: AMapNaviDriveView = {
        let view = AMapNaviDriveView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = self
        view.showGreyAfterPass = true
        view.autoZoomMapLevel = true
        view.trackingMode = AMapNaviViewTrackingMode.carNorth
        view.mapViewModeType = AMapNaviViewMapModeType.night
        return view
    }()

    
    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }
    
    var compositeManager : AMapNaviCompositeManager!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLocationManager()
//        self.compositeManager = AMapNaviCompositeManager.init()
//        self.compositeManager.delegate = self
        AMapNaviDriveManager.sharedInstance().delegate = self
        AMapNaviDriveManager.sharedInstance().allowsBackgroundLocationUpdates = true
        AMapNaviDriveManager.sharedInstance().pausesLocationUpdatesAutomatically = false
        setupUI()
        //将driveView添加为导航数据的Representative，使其可以接收到导航诱导数据
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(driveView)
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(self)

//        self.compositeManager.presentRoutePlanViewController(withOptions: nil)
    }
    
    // MARK: - 初始化配置
    private func setupLocationManager() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    // MARK: - UI 布局实现
    private func setupUI() {
        let buttonStackView = UIStackView()
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .fillEqually
        buttonStackView.spacing = 10

        homeButton.setTitle("🏠 回家", for: .normal)
        homeButton.backgroundColor = .systemBlue
        homeButton.setTitleColor(.white, for: .normal)
        homeButton.layer.cornerRadius = 8
        homeButton.addTarget(self, action: #selector(homeButtonTapped), for: .touchUpInside)
        
        officeButton.setTitle("🏢 去公司", for: .normal)
        officeButton.backgroundColor = .systemOrange
        officeButton.setTitleColor(.white, for: .normal)
        officeButton.layer.cornerRadius = 8
        officeButton.addTarget(self, action: #selector(officeButtonTapped), for: .touchUpInside)
        
        buttonStackView.addArrangedSubview(homeButton)
        buttonStackView.addArrangedSubview(officeButton)

        view.addSubviews([amapView,searchBar,buttonStackView,searchResultsTableView,startNavigationButton,preferenceView,driveView])
        amapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        searchBar.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.height.equalTo(44)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        buttonStackView.snp.makeConstraints { make in
            make.height.equalTo(40)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(self.searchBar.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        searchResultsTableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(buttonStackView.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.height.equalTo(250.adapter)
        }
                
        startNavigationButton.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
            make.height.equalTo(50)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
        
        preferenceView.snp.makeConstraints { make in
            make.height.equalTo(30)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(buttonStackView.snp.bottom).offset(CGFloat.GlobalItemSpacing)
        }
        
        driveView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(self.searchResultsTableView.snp.bottom)
            make.height.equalTo(300)
        }
    }
    
    // MARK: - 按钮交互逻辑
    @objc private func homeButtonTapped() {
        searchBar.resignFirstResponder()
        routeToSavedLocation(key: "PT_HomeLocation")
    }
    
    @objc private func officeButtonTapped() {
        searchBar.resignFirstResponder()
        routeToSavedLocation(key: "PT_OfficeLocation")
    }
    
    @objc private func startNavigationTapped() {
        guard let destination = currentDestination else { return }
        // 核心调用：触发底层蓝牙发送逻辑
        PTMapKitNavigationHelper.shared.startNavigation(to: destination)
        
        // 可以在这里收起按钮，或者进入纯粹的导航视角
        startNavigationButton.setTitle("导航中...", for: .normal)
        startNavigationButton.backgroundColor = .systemGray
        startNavigationButton.isEnabled = false
    }
    
    var userCurrentLocation = AMapNaviPoint.location(withLatitude: 0, longitude: 0)!
    
    // MARK: - 路线规划与绘制
    private func planRoute(to destination: CLLocationCoordinate2D, title: String) {
        currentDestination = destination
        guard userCurrentLocation.latitude != 0, userCurrentLocation.longitude != 0 else {
            PTProgressHUD.show(text: "正在获取精准定位，请稍后再试...")
            return
        }
        PTProgressHUD.show(text: "正在为您规划高德路线...")
        let endPoint = AMapNaviPoint.location(withLatitude: destination.latitude, longitude: destination.longitude)!
        let value = AMapNaviDriveManager.sharedInstance().calculateDriveRoute(withStart: [userCurrentLocation],
                                                                  end: [endPoint],
                                                                  wayPoints: nil,
                                                                  drivingStrategy: preferenceView.strategy(isMultiple: isMultipleRoutePlan))
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\(value)")
    }
    
    // MARK: - 数据持久化管理
    private func saveLocation(coordinate: CLLocationCoordinate2D, key: String) {
        let dict: [String: Double] = ["lat": coordinate.latitude, "lon": coordinate.longitude]
        UserDefaults.standard.set(dict, forKey: key)
        
        let name = key.contains("Home") ? "家" : "公司"
        let alert = UIAlertController(title: "保存成功", message: "已成功将该地址设为\(name)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
    
    private func routeToSavedLocation(key: String) {
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double],
              let lat = dict["lat"], let lon = dict["lon"] else {
            let alert = UIAlertController(title: "提示", message: "您尚未设置该地址，请先在搜索列表中长按或选择地址进行保存。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let name = key.contains("Home") ? "家" : "公司"
        planRoute(to: coordinate, title: name)
    }
}

// MARK: - 搜索补全与列表代理
extension PTMotoNavigationViewController: UISearchBarDelegate, UITableViewDelegate, UITableViewDataSource {
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBarText(text: searchBar.text ?? "")
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBarText(text: searchBar.text ?? "")
    }
    
    func searchBarText(text:String) {
        if text.isEmpty {
            searchResultsTableView.isHidden = true
        } else {
            searchResultsTableView.isHidden = false
            searchPOI(withKeyword: text)
        }
    }
        
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return amapSearchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let result = amapSearchResults[indexPath.row]
        cell.textLabel?.text = result.title + "\(result.coordinate.latitude)+\(result.coordinate.longitude)"
        cell.detailTextLabel?.text = result.subtitle
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        view.endEditing(true) // 收起键盘
        searchResultsTableView.isHidden = true // 隐藏列表
        
        let completion = amapSearchResults[indexPath.row]
        
        // 弹出交互菜单
        let actionSheet = UIAlertController(title: completion.title, message: "请选择您要执行的操作", preferredStyle: .actionSheet)
        
        // 选项 1: 规划路线
        actionSheet.addAction(UIAlertAction(title: "📍 规划路线", style: .default) { [weak self] _ in
            self?.performSearchAndRoute(completion: completion)
        })
        
        // 选项 2: 设为家
        actionSheet.addAction(UIAlertAction(title: "🏠 设为家", style: .default) { [weak self] _ in
            self?.performSearchAndSave(completion: completion, key: "PT_HomeLocation")
        })
        
        // 选项 3: 设为公司
        actionSheet.addAction(UIAlertAction(title: "🏢 设为公司", style: .default) { [weak self] _ in
            self?.performSearchAndSave(completion: completion, key: "PT_OfficeLocation")
        })
        
        actionSheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(actionSheet, animated: true)
    }
    
    // 解析具体的坐标并路线规划
    private func performSearchAndRoute(completion: MAPointAnnotation) {
        self.planRoute(to: completion.coordinate, title: completion.title)
        amapView.removeAnnotations(amapView.annotations)
        let beginAnnotation = NaviPointAnnotation()
        beginAnnotation.coordinate = CLLocationCoordinate2D(latitude: Double(userCurrentLocation.latitude), longitude: Double(userCurrentLocation.longitude))
        beginAnnotation.title = "起始点"
        beginAnnotation.naviPointType = .start
        
        amapView.addAnnotation(beginAnnotation)
        
        let endAnnotation = NaviPointAnnotation()
        endAnnotation.coordinate = CLLocationCoordinate2D(latitude: Double(completion.coordinate.latitude), longitude: Double(completion.coordinate.longitude))
        endAnnotation.title = "终点"
        endAnnotation.naviPointType = .end
        
        amapView.addAnnotation(endAnnotation)
    }
    
    // 解析具体的坐标并保存
    private func performSearchAndSave(completion: MAPointAnnotation, key: String) {
        self.saveLocation(coordinate: completion.coordinate, key: key)
    }
}

extension PTMotoNavigationViewController:MAMapViewDelegate {
    func mapView(_ mapView: MAMapView!, rendererFor overlay: MAOverlay!) -> MAOverlayRenderer! {
        
        if let selectableOverlay = overlay as? SelectableOverlay {
            // 使用你的 SelectableOverlay 里的 polyline 来初始化渲染器
            let polylineRenderer = MAPolylineRenderer(overlay: selectableOverlay.overlay)
            
            // 设置路线宽度和颜色
            polylineRenderer?.lineWidth = 8.0
            polylineRenderer?.strokeColor = selectableOverlay.selected ? selectableOverlay.selectedColor : selectableOverlay.reguarColor
            
            return polylineRenderer
        }
        return nil
    }
    
    // 🚨 核心修复 2：移除 @nonobjc，允许高德 SDK 调用大头针渲染器
    func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
        
        // 过滤我们自定义的导航大头针
        if let naviAnno = annotation as? NaviPointAnnotation {
            let annotationIdentifier = "NaviPointAnnotationIdentifier"
            
            var pointAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: annotationIdentifier) as? MAPinAnnotationView
            
            if pointAnnotationView == nil {
                pointAnnotationView = MAPinAnnotationView(annotation: naviAnno, reuseIdentifier: annotationIdentifier)
            }
            
            pointAnnotationView?.animatesDrop = false
            pointAnnotationView?.canShowCallout = true
            pointAnnotationView?.isDraggable = false
            
            // 🚨 根据类型设置颜色，这里生效后，起点就会变回绿色！
            if naviAnno.naviPointType == .start {
                pointAnnotationView?.pinColor = .green // 起点为绿色
            } else if naviAnno.naviPointType == .end {
                pointAnnotationView?.pinColor = .red   // 终点为红色
            }
            
            return pointAnnotationView
        }
        return nil
    }
}

extension PTMotoNavigationViewController:AMapLocationManagerDelegate {
    func amapLocationManager(_ manager: AMapLocationManager!, doRequireLocationAuth locationManager: CLLocationManager!) {
        locationManager.requestAlwaysAuthorization()
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didChange status: CLAuthorizationStatus) {
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: (any Error)!) {
        
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!, reGeocode: AMapLocationReGeocode!) {
        userCurrentLocation = AMapNaviPoint.location(withLatitude: location.coordinate.latitude, longitude: location.coordinate.longitude)!
    }
}

extension PTMotoNavigationViewController:AMapSearchDelegate {
    func searchPOI(withKeyword keyword: String?) {
        
        if keyword == nil || keyword! == "" {
            return
        }
        
        let request = AMapPOIKeywordsSearchRequest()
        request.keywords = keyword
        request.showFieldsType = .all
        request.city = "江门"
        search.aMapPOIKeywordsSearch(request)
    }
    
    func onPOISearchDone(_ request: AMapPOISearchBaseRequest!, response: AMapPOISearchResponse!) {
        for aPOI in response.pois {
            let coordinate = CLLocationCoordinate2D(latitude: CLLocationDegrees(aPOI.location.latitude), longitude: CLLocationDegrees(aPOI.location.longitude))
            let anno = MAPointAnnotation()
            anno.coordinate = coordinate
            anno.title = aPOI.name
            anno.subtitle = aPOI.address
            self.amapSearchResults.append(anno)
        }
        searchResultsTableView.reloadData()
    }
}

extension PTMotoNavigationViewController:AMapNaviDriveManagerDelegate {
    func showNaviRoutes() {
        
        guard let allRoutes = AMapNaviDriveManager.sharedInstance().naviRoutes else {
            return
        }
        
        amapView.removeOverlays(amapView.overlays)
        routeIndicatorInfoArray.removeAll()
        
        //将路径显示到地图上
        for (aNumber, aRoute) in allRoutes {
            
            //添加路径Polyline
            var coords = [CLLocationCoordinate2D]()
            for coordinate in aRoute.routeCoordinates {
                coords.append(CLLocationCoordinate2D(latitude: Double(coordinate.latitude), longitude: Double(coordinate.longitude)))
            }
            
            let polyline = MAPolyline(coordinates: &coords, count: UInt(aRoute.routeCoordinates.count))!
            let selectablePolyline = SelectableOverlay(aOverlay: polyline)
            selectablePolyline.routeID = Int( truncating: aNumber)
            
            amapView.add(selectablePolyline)
            
            //更新CollectonView的信息
            let title = String(format: "路径ID:%d | 路径计算策略:%d", Int( truncating: aNumber), preferenceView.strategy(isMultiple: isMultipleRoutePlan).rawValue)
            let subtitle = String(format: "长度:%d米 | 预估时间:%d秒 | 分段数:%d", aRoute.routeLength, aRoute.routeTime, aRoute.routeSegments.count)
            let info = RouteCollectionViewInfo(routeID: Int( truncating: aNumber), title: title, subTitle: subtitle)
            
            routeIndicatorInfoArray.append(info)
        }
        
        amapView.showAnnotations(amapView.annotations, animated: false)
        
        if let first = routeIndicatorInfoArray.first {
            self.startNavigationButton.setTitle("🚀 开始导航 \(first.subTitle)", for: .normal)
            selectNaviRouteWithID(routeID: first.routeID)
        }
    }
    
    func selectNaviRouteWithID(routeID: Int) {
        //在开始导航前进行路径选择
        if AMapNaviDriveManager.sharedInstance().selectNaviRoute(withRouteID: routeID) {
            selecteOverlayWithRouteID(routeID: routeID)
        } else {
            PTNSLogConsole("路径选择失败!")
        }
    }
    
    func selecteOverlayWithRouteID(routeID: Int) {
        guard let allOverlays = amapView.overlays else {
            return
        }
        
        for (index, aOverlay) in allOverlays.enumerated() {
            
            if let selectableOverlay = aOverlay as? SelectableOverlay {
                
                /* 获取overlay对应的renderer. */
                guard let overlayRenderer = amapView.renderer(for: selectableOverlay) as? MAPolylineRenderer else {
                    return
                }
                
                if selectableOverlay.routeID == routeID {
                    /* 设置选中状态. */
                    selectableOverlay.selected = true
                    
                    /* 修改renderer选中颜色. */
                    overlayRenderer.fillColor = selectableOverlay.selectedColor
                    overlayRenderer.strokeColor = selectableOverlay.selectedColor
                    
                    /* 修改overlay覆盖的顺序. */
                    amapView.exchangeOverlay(at: UInt(index), withOverlayAt: UInt(allOverlays.count - 1))
                }
                else {
                    /* 设置选中状态. */
                    selectableOverlay.selected = false
                    
                    /* 修改renderer选中颜色. */
                    overlayRenderer.fillColor = selectableOverlay.reguarColor
                    overlayRenderer.strokeColor = selectableOverlay.reguarColor
                }
            }
        }
        
        self.startNavigationButton.isHidden = false
        self.startNavigationButton.isEnabled = true
        self.startNavigationButton.backgroundColor = .systemGreen
        AMapNaviDriveManager.sharedInstance().startEmulatorNavi()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        let error = error as NSError
        PTNSLogConsole("error:{%d - %@}", error.code, error.localizedDescription)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        let error = error as NSError
        PTNSLogConsole("CalculateRouteFailure:{%d - %@}", error.code, error.localizedDescription)
    }

    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
        //算路成功后显示路径
        showNaviRoutes()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, postRouteNotification notifyData: AMapNaviRouteNotifyData) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>\(String(describing: notifyData.roadName))")
    }
            
    func driveManager(_ manager: AMapNaviDriveManager?, onUpdateNaviSpeedLimitSection speed: Int) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>>>>>\(speed)")
    }
        
    private func convertAMapIconToPTManeuver(iconType: AMapNaviIconType) -> UInt8 {
        switch iconType {
        case .none, .default:
            return PTManeuverMap.straight
        case .straight:
            return PTManeuverMap.straight
        case .left:
            return PTManeuverMap.quiteLeft
        case .right:
            return PTManeuverMap.quiteRight
        case .leftFront:
            return PTManeuverMap.lightLeft
        case .rightFront:
            return PTManeuverMap.lightRight
        case .leftBack:
            return PTManeuverMap.heavyLeft
        case .rightBack:
            return PTManeuverMap.heavyRight
        case .entryLeftRingUTurn:
            return PTManeuverMap.uTurnLeft
        case .entryLeftRingRight:
            return PTManeuverMap.uTurnRight
        case .arrivedWayPoint:
            return PTManeuverMap.straight // 到达途经点，通常保持直行即可
        case .arrivedDestination:
            return PTManeuverMap.arrive
        default:
            return PTManeuverMap.straight
        }
    }
}

extension PTMotoNavigationViewController : AMapNaviDriveViewDelegate {
    
    func driveViewCloseButtonClicked(_ driveView: AMapNaviDriveView) {
        
        //停止导航
        AMapNaviDriveManager.sharedInstance().stopNavi()
        AMapNaviDriveManager.sharedInstance().removeDataRepresentative(driveView)
        
//        //停止语音
//        SpeechSynthesizer.Shared.stopSpeak()
//
//        _ = navigationController?.popViewController(animated: true)
    }
    
    func driveView(_ view: AMapNaviDriveView, didChangeTo state: AMapNaviDriveViewState) {
        
    }
    
}

extension PTMotoNavigationViewController {
    func normalizedRemainDistance(_ remainDistance: Int) -> String {
        guard remainDistance >= 0 else {
            return ""
        }
        
        if remainDistance >= 1000 {
            var kiloMeter = Double(remainDistance) / 1000.0
            
            if remainDistance % 1000 >= 1000 {
                kiloMeter -= 0.05
                return String(format: "%.1f公里", kiloMeter)
            }
            else {
                return String(format: "%.0f公里", kiloMeter)
            }
        }
        else {
            return String(format: "%d米", remainDistance)
        }
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update naviInfo: AMapNaviInfo?) {
        guard let naviInfo = naviInfo else {
            return
        }
        let remainDis = normalizedRemainDistance(naviInfo.routeRemainDistance)
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\(remainDis)")
//        PTBluetoothServerManager.shared.sendNavigation(info: navInfo)
    }
}
