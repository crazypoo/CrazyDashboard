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
import SafeSFSymbols

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
        let itemCount:Int = 4
        
        let singleWidth = (CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace * 2 - CGFloat(itemCount + 1) * CGFloat.GlobalItemSpacing - 44 * 2 - CGFloat.GlobalItemSpacing) / CGFloat(itemCount)
        
        avoidCongestion = buttonForTitle("躲避拥堵")
        avoidCongestion.addTarget(self, action: #selector(self.avoidCongestionAction(sender:)), for: .touchUpInside)
        addSubview(avoidCongestion)
        avoidCongestion.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(singleWidth)
        }
        
        avoidCost = buttonForTitle("避免收费")
        avoidCost.addTarget(self, action: #selector(self.avoidCostAction(sender:)), for: .touchUpInside)
        addSubview(avoidCost)
        avoidCost.snp.makeConstraints { make in
            make.left.equalTo(self.avoidCongestion.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }
        
        avoidHighway = buttonForTitle("不走高速")
        avoidHighway.addTarget(self, action: #selector(self.avoidHighwayAction(sender:)), for: .touchUpInside)
        addSubview(avoidHighway)
        avoidHighway.snp.makeConstraints { make in
            make.left.equalTo(self.avoidCost.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }

        prioritiseHighway = buttonForTitle("高速优先")
        prioritiseHighway.addTarget(self, action: #selector(self.prioritiseHighwayAction(sender:)), for: .touchUpInside)
        addSubview(prioritiseHighway)
        prioritiseHighway.snp.makeConstraints { make in
            make.left.equalTo(self.avoidHighway.snp.right).offset(CGFloat.GlobalItemSpacing)
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
    
    private func buttonForTitle(_ title: String) -> PTBaseButton {
        let reBtn = PTBaseButton(type: .custom)
        
        reBtn.layer.borderColor = UIColor.lightGray.cgColor
        reBtn.layer.borderWidth = 1.0
        reBtn.layer.cornerRadius = 5
        reBtn.setTitle(title, for: .normal)
        reBtn.setTitleColor(UIColor.white, for: .normal)
        reBtn.setTitleColor(PTDashboardConfig.shared.appMainColor, for: .selected)
        reBtn.titleLabel?.font = .appfont(size: 13)
        
        return reBtn
    }
    
    private func changeButtonState(_ button: UIButton, selected: Bool) {
        button.isSelected = selected
        button.layer.borderColor = button.isSelected ? PTDashboardConfig.shared.appMainColor.cgColor : UIColor.lightGray.cgColor
    }
}

class PTMotoNavigationViewController: PTBaseViewController {

    var routeIndicatorInfoArray = [RouteCollectionViewInfo]()

    var currentSpeedLimit:UInt8 = 0
    
    private lazy var amapView:MAMapView = {
        let view = MAMapView()
        view.delegate = self
        view.showsUserLocation = true
        view.userTrackingMode = .follow
        view.mapType = .standardNight
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
        view.searchPlaceholderColor = .black
        view.searchPlaceholderFont = .appfont(size: 16)
        view.delegate = self
        view.searchBarStyle = .minimal
        view.backgroundColor = .clear
        view.searchTextFieldBackgroundColor = .clear
        view.searchBarOutViewColor = .clear
        view.searchBarTextFieldBorderColor = .clear
        view.searchBarTextFieldCornerRadius = PTAppBaseConfig.share.navBarButtonSize / 2
        view.searchBarTextFieldBorderWidth = 0
        view.cursorColor = PTDashboardConfig.shared.appMainColor
        view.searchTextColor = .black
        view.bounds = .init(origin: .zero, size: .init(width: 100, height: PTAppBaseConfig.share.navBarButtonSize))
        return view
    }()
    private lazy var searchResultsTableView:UITableView = {
        let view = UITableView()
        view.delegate = self
        view.dataSource = self
        view.isHidden = true // 默认隐藏
        view.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        return view
    }()
    private lazy var homeButton:PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setTitle("🏠", for: .normal)
        view.addActionHandlers(handler: { _ in
            self.routeToSavedLocation(key: "PT_HomeLocation")
        })
        return view
    }()
    private lazy var officeButton:PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setTitle("🏢", for: .normal)
        view.addActionHandlers(handler: { _ in
            self.routeToSavedLocation(key: "PT_OfficeLocation")
        })
        return view
    }()
    private lazy var startNavigationButton:UIButton = {
        let view = UIButton(type: .system)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setTitle("🚀 开始导航", for: .normal)
        view.titleLabel?.font = .appfont(size: 18)
        view.backgroundColor = .systemGreen
        view.setTitleColor(.white, for: .normal)
        view.layer.cornerRadius = 12
        view.isHidden = true // 只有规划好路线才显示
        view.addActionHandlers(handler: { _ in
            self.startNavigationTapped()
            self.driveView.isHidden = false
            
            if self.testButton.isSelected {
                AMapNaviDriveManager.sharedInstance().startEmulatorNavi()
            } else {
                AMapNaviDriveManager.sharedInstance().startGPSNavi()
            }
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
    var isMultipleRoutePlan = false

    var loadCurrentLocation:Bool = false
    var currentCity:String = ""
    
    lazy var driveView: AMapNaviDriveView = {
        let view = AMapNaviDriveView()
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.delegate = self
        view.showGreyAfterPass = true
        view.autoZoomMapLevel = true
        view.trackingMode = AMapNaviViewTrackingMode.carNorth
        view.mapViewModeType = AMapNaviViewMapModeType.night
        view.isHidden = true
        return view
    }()
    
    lazy var testButton:UIButton = {
        let baseImage = UIImage(.testtube._2)
        let view = UIButton(type: .custom)
        view.setImage(baseImage.withTintColor(.lightGray, renderingMode: .alwaysOriginal), for: .normal)
        view.setImage(baseImage.withTintColor(PTDashboardConfig.shared.appMainColor, renderingMode: .alwaysOriginal), for: .selected)
        view.isSelected = false
        view.bounds = .init(origin: .zero, size: .init(width: PTAppBaseConfig.share.navBarButtonSize, height: PTAppBaseConfig.share.navBarButtonSize))
        view.addActionHandlers(handler: { sender in
            sender.isSelected.toggle()
        })
        return view
    }()
    
    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomTitleView(searchBar)
        setCustomRightButtons(buttons: [testButton])
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLocationManager()
        AMapNaviDriveManager.sharedInstance().delegate = self
        AMapNaviDriveManager.sharedInstance().allowsBackgroundLocationUpdates = true
        AMapNaviDriveManager.sharedInstance().pausesLocationUpdatesAutomatically = false
        setupUI()
        //将driveView添加为导航数据的Representative，使其可以接收到导航诱导数据
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(driveView)
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(self)
    }
    
    // MARK: - 初始化配置
    private func setupLocationManager() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    // MARK: - UI 布局实现
    private func setupUI() {
        NotificationCenter.default.addObserver(self, selector: #selector(dashBoardReload), name: MotorcycleDashBoardChange, object: nil)

        view.addSubviews([amapView,homeButton,officeButton,searchResultsTableView,startNavigationButton,preferenceView,driveView])
        amapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        let buttonSize:CGFloat = 44
        homeButton.snp.makeConstraints { make in
            make.size.equalTo(buttonSize)
            make.left.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
        }
        
        officeButton.snp.makeConstraints { make in
            make.size.top.equalTo(self.homeButton)
            make.left.equalTo(self.homeButton.snp.right).offset(CGFloat.GlobalItemSpacing)
        }
        homeButton.layoutIfNeeded()
        officeButton.layoutIfNeeded()
        homeButton.viewCorner(radius: buttonSize / 2)
        officeButton.viewCorner(radius: buttonSize / 2)

        searchResultsTableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalTo(homeButton.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.height.equalTo(250.adapter)
        }
        searchResultsTableView.layoutIfNeeded()
        searchResultsTableView.viewCorner(radius: 16)
                
        startNavigationButton.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
            make.height.equalTo(50)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
        
        preferenceView.snp.makeConstraints { make in
            make.height.top.equalTo(self.homeButton)
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.left.equalTo(self.officeButton.snp.right).offset(CGFloat.GlobalItemSpacing)
        }
        
        driveView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(self.searchResultsTableView)
            make.bottom.equalTo(self.startNavigationButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
        }
    }
        
    @objc private func startNavigationTapped() {
        
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
        let _ = AMapNaviDriveManager.sharedInstance().calculateDriveRoute(withStart: [userCurrentLocation],
                                                                          end: [endPoint],
                                                                          wayPoints: nil,
                                                                          drivingStrategy: preferenceView.strategy(isMultiple: isMultipleRoutePlan))
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
        searchBar.resignFirstResponder()
        searchResultsTableView.isHidden = true
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
        setPointPin(location: coordinate)
    }
    
    @objc func dashBoardReload() {
        self.searchBar.cursorColor = PTDashboardConfig.shared.appMainColor
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
            searchPOI(withKeyword: text)
        }
    }
        
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return amapSearchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let result = amapSearchResults[indexPath.row]
        cell.textLabel?.font = .appfont(size: 16)
        cell.detailTextLabel?.font = .appfont(size: 13)
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
        self.searchBar.resignFirstResponder()
        self.planRoute(to: completion.coordinate, title: completion.title)
        setPointPin(location: completion.coordinate)
    }
    
    // 解析具体的坐标并保存
    private func performSearchAndSave(completion: MAPointAnnotation, key: String) {
        self.saveLocation(coordinate: completion.coordinate, key: key)
    }
}

extension PTMotoNavigationViewController:MAMapViewDelegate {
    func setPointPin(location: CLLocationCoordinate2D) {
        amapView.removeAnnotations(amapView.annotations)
        let beginAnnotation = NaviPointAnnotation()
        beginAnnotation.coordinate = CLLocationCoordinate2D(latitude: Double(userCurrentLocation.latitude), longitude: Double(userCurrentLocation.longitude))
        beginAnnotation.title = "起始点"
        beginAnnotation.naviPointType = .start
        
        amapView.addAnnotation(beginAnnotation)
        
        let endAnnotation = NaviPointAnnotation()
        endAnnotation.coordinate = location
        endAnnotation.title = "终点"
        endAnnotation.naviPointType = .end
        
        amapView.addAnnotation(endAnnotation)
    }
    
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
        if !loadCurrentLocation {
            let regeo = AMapReGeocodeSearchRequest()
            regeo.location = AMapGeoPoint.location(withLatitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            regeo.requireExtension = true
            self.search.aMapReGoecodeSearch(regeo)
        }
    }
    
    func onReGeocodeSearchDone(_ request: AMapReGeocodeSearchRequest!, response: AMapReGeocodeSearchResponse!) {
        currentCity = response.regeocode.addressComponent.city
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
        request.city = currentCity
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
        if !self.amapSearchResults.isEmpty {
            searchResultsTableView.isHidden = false
            searchResultsTableView.reloadData()
        } else {
            searchResultsTableView.isHidden = true
            searchResultsTableView.reloadData()
        }
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
            self.startNavigationButton.setTitle("🚀 开始导航", for: .normal)
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
                } else {
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
        self.currentSpeedLimit = UInt8(speed)
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
            return PTManeuverMap.heavyLeft // 0x0C 急左转
        case .rightBack:
            return PTManeuverMap.heavyRight // 0x07 急右转[cite: 2]
        case .entryLeftRingUTurn:
            return PTManeuverMap.uTurnLeft
        case .entryLeftRingRight:
            return PTManeuverMap.uTurnRight
        case .arrivedWayPoint:
            return PTManeuverMap.straight
        case .arrivedDestination:
            return PTManeuverMap.arrive // 0x2C 到达[cite: 2]
        // 🚨 新增：环岛处理逻辑
        case .enterRoundabout:
            // 协议规定右侧环岛 1 号出口为 0x13[cite: 2]。
            // 如果高德在 AMapNaviInfo 中提供了环岛出口编号 (ringRoundaboutExitCount)，你可以动态加上该编号减 1。
            // 这里提供基础的 1 号出口映射作为安全回退机制。
            return PTManeuverMap.roundaboutRightBase
            
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
        self.driveView.isHidden = true
        self.startNavigationButton.isHidden = true
        self.startNavigationButton.isEnabled = false
        self.amapView.removeAnnotations(amapView.annotations)
        self.amapView.removeOverlays(amapView.overlays)
//        //停止语音
//        SpeechSynthesizer.Shared.stopSpeak()
//
//        _ = navigationController?.popViewController(animated: true)
    }
    
    func driveView(_ view: AMapNaviDriveView, didChangeTo state: AMapNaviDriveViewState) {
        
    }
}

extension PTMotoNavigationViewController:AMapNaviDriveDataRepresentable {
         
    func driveManager(_ driveManager: AMapNaviDriveManager, update cameraInfos: [AMapNaviCameraInfo]?) {
        if let firstCamera = cameraInfos?.first {
            // cameraSpeed 通常代表该路段限速，为 0 时表示无限速或未知
            if firstCamera.cameraSpeed > 0 {
                self.currentSpeedLimit = UInt8(firstCamera.cameraSpeed)
            }
        }
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, update naviInfo: AMapNaviInfo?) {
        guard let naviInfo = naviInfo else {
            return
        }
        // --- 核心逻辑开始 ---
        // 1. 获取距离下一个转弯动作的剩余距离 (米)
        let distanceToNextManeuver = naviInfo.segmentRemainDistance
        
        // 2. 提取路名，并强制转为无声调拼音/英文，防止车机乱码
        let rawNextRoad = naviInfo.nextRoadName ?? ""
        let rawCurrentRoad = naviInfo.currentRoadName ?? ""
        let safeNextRoad = rawNextRoad.toMotorcycleCompatiblePinyin()
        let safeCurrentRoad = rawCurrentRoad.toMotorcycleCompatiblePinyin()
        
        // 3. 将高德的转向图标枚举转换为车机的动作码
        let maneuverCode = convertAMapIconToPTManeuver(iconType: naviInfo.iconType)
        
        // 4. 组装车机数据模型 (限速字段使用全局变量 currentSpeedLimit)
        let info = PTNavigationInfo(
            nextManeuver: maneuverCode,
            metersToNextManeuver: UInt32(max(0, distanceToNextManeuver)),
            nameNextRoad: safeNextRoad,
            nameCurrentRoad: safeCurrentRoad,
            currentSpeedLimit: self.currentSpeedLimit,
            distanceToDestination: UInt32(max(0, naviInfo.routeRemainDistance)),
            estimatedTimeToDestinationSec: max(0, naviInfo.routeRemainTime)
        )
        
        // 打印调试日志
//        PTProgressHUD.show(text: "🚀 高德诱导 -> 动作: \(maneuverCode), 距转弯: \(distanceToNextManeuver)m, 限速: \(self.currentSpeedLimit)km/h")
        
        // 5. 核心动作：通过蓝牙将数据泵送给摩托车！
        PTBluetoothServerManager.shared.sendNavigation(info: info)
    }
}
