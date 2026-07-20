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

class PTMotoNavigationViewController: PTBaseViewController {

    lazy var tap:UIButton = {
        let view = UIButton(type: .custom)
        view.addActionHandlers { sender in
            // 假设你要导航到某个坐标 (比如北京天安门)
            let destinationCoordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

            // 触发导航路线计算。一旦计算成功，它会自动在后台监听 GPS 并向摩托车发数据！
            PTMapKitNavigationHelper.shared.startNavigation(to: destinationCoordinate)
        }
        view.backgroundColor = .systemBlue
        return view
    }()
    
    // MARK: - UI 组件
    private let mapView = MKMapView()
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
        view.addTarget(self, action: #selector(startNavigationTapped), for: .touchUpInside)
        view.addActionHandlers(handler: { _ in
            self.startNavigationTapped()
        })
        return view
    }()
    
    // MARK: - 核心管理器
    private let locationManager = CLLocationManager()
    private var searchCompleter = MKLocalSearchCompleter()
    private var searchResults: [MKLocalSearchCompletion] = []
    
    // MARK: - 状态变量
    private var currentDestination: CLLocationCoordinate2D?
    private var currentRouteOverlay: MKPolyline?

    open override func preferredNavigationBarStyle() -> PTNavigationBarStyle {
        return .solid(.clear)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLocationManager()
        setupUI()
        setupSearchCompleter()
    }
    
    // MARK: - 初始化配置
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5 // 每移动 5 米更新一次
        locationManager.startUpdatingLocation()
        
        mapView.showsUserLocation = true
        mapView.delegate = self
    }
    
    private func setupSearchCompleter() {
        searchCompleter.delegate = self
        // 限制搜索结果为位置
        searchCompleter.resultTypes = .address
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

        mapView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubviews([mapView,searchBar,buttonStackView,searchResultsTableView,startNavigationButton])
        mapView.snp.makeConstraints { make in
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
    
    // MARK: - 路线规划与绘制
    private func planRoute(to destination: CLLocationCoordinate2D, title: String) {
        currentDestination = destination
        
        // 1. 清理旧数据
        if let existingOverlay = currentRouteOverlay {
            mapView.removeOverlay(existingOverlay)
        }
        mapView.removeAnnotations(mapView.annotations)
        
        // 2. 添加终点大头针
        let annotation = MKPointAnnotation()
        annotation.coordinate = destination
        annotation.title = title
        mapView.addAnnotation(annotation)
        
        // 3. 构建请求
        guard let currentLocation = locationManager.location else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: currentLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        
        // 4. 发起路线计算
        let directions = MKDirections(request: request)
        directions.calculate { [weak self] response, error in
            guard let self = self, let route = response?.routes.first else {
                print("路线规划失败: \(error?.localizedDescription ?? "")")
                return
            }
            
            // 5. 将折线绘制到地图上
            self.currentRouteOverlay = route.polyline
            self.mapView.addOverlay(route.polyline)
            
            // 6. 调整地图缩放，使其同时显示起点和终点
            var rect = route.polyline.boundingMapRect
            // 增加一点边距
            rect = self.mapView.mapRectThatFits(rect, edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 100, right: 50))
            self.mapView.setRegion(MKCoordinateRegion(rect), animated: true)
            
            // 7. 显示开始导航按钮
            self.startNavigationButton.isHidden = false
            self.startNavigationButton.setTitle("🚀 开始导航 (\(Int(route.expectedTravelTime / 60))分钟)", for: .normal)
            self.startNavigationButton.isEnabled = true
            self.startNavigationButton.backgroundColor = .systemGreen
        }
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

// MARK: - 地图代理 (用于渲染折线)
extension PTMotoNavigationViewController: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = .systemBlue
            renderer.lineWidth = 5
            return renderer
        }
        return MKOverlayRenderer(overlay: overlay)
    }
}

// MARK: - CoreLocation 代理
extension PTMotoNavigationViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 提供初始的搜索区域基准
        if let location = locations.last {
            searchCompleter.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 5000, longitudinalMeters: 5000)
        }
    }
}

// MARK: - 搜索补全与列表代理
extension PTMotoNavigationViewController: UISearchBarDelegate, MKLocalSearchCompleterDelegate, UITableViewDelegate, UITableViewDataSource {
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            searchResultsTableView.isHidden = true
        } else {
            searchResultsTableView.isHidden = false
            searchCompleter.queryFragment = searchText
        }
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results
        searchResultsTableView.reloadData()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let result = searchResults[indexPath.row]
        cell.textLabel?.text = result.title
        cell.detailTextLabel?.text = result.subtitle
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        view.endEditing(true) // 收起键盘
        searchResultsTableView.isHidden = true // 隐藏列表
        
        let completion = searchResults[indexPath.row]
        
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
    private func performSearchAndRoute(completion: MKLocalSearchCompletion) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        search.start { [weak self] response, error in
            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            self?.planRoute(to: coordinate, title: completion.title)
        }
    }
    
    // 解析具体的坐标并保存
    private func performSearchAndSave(completion: MKLocalSearchCompletion, key: String) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        search.start { [weak self] response, error in
            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            self?.saveLocation(coordinate: coordinate, key: key)
        }
    }
}
