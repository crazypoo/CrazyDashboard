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
import AttributedString
import CarPlay
import MultipeerConnectivity

public let PTCarPlayStopNavNotification = NSNotification.Name("PTCarPlayStopNavNotification")
public let PTCarPlayStarNavNotification = NSNotification.Name("PTCarPlayStarNavNotification")

enum NaviPointAnnotationType: Int {
    case start
    case way
    case end
    case parking
}

class NaviPointAnnotation: MAPointAnnotation {
    var naviPointType: NaviPointAnnotationType?
}

class PTPeerAnnotation: MAPointAnnotation {
    var peerID: MCPeerID!
    var course: Double = 0.0 // 记录车头方向
    var avatarImage: UIImage? // 暂存队友的真实头像
}

extension UIImage {
    func pt_toMapCircleAvatar(size: CGSize = CGSize(width: 32, height: 32)) -> UIImage? {
        return self.transformImage(size: size)
    }
}

struct RouteCollectionViewInfo {
    var routeID: Int
    var title: String
    var subTitle: String
    var isSelected:Bool
    var distance:Double
}

class SelectableOverlay: MABaseOverlay {
    var routeID: Int = 0
    var selected = false
    var selectedColor = PTDashboardConfig.shared.appMainColor
    var reguarColor = PTDashboardConfig.shared.appMainColor.withAlphaComponent(0.6)
    
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
        
        pt_viewObserverLanguage {
            self.avoidCongestion.setTitle(PTDashboardConfig.languageFunc(text: "route_plan1"), for: .normal)
            self.avoidCost.setTitle(PTDashboardConfig.languageFunc(text: "route_plan2"), for: .normal)
            self.avoidHighway.setTitle(PTDashboardConfig.languageFunc(text: "route_plan3"), for: .normal)
            self.prioritiseHighway.setTitle(PTDashboardConfig.languageFunc(text: "route_plan4"), for: .normal)
        }
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
        
        avoidCongestion = buttonForTitle(PTDashboardConfig.languageFunc(text: "route_plan1"))
        avoidCongestion.addTarget(self, action: #selector(self.avoidCongestionAction(sender:)), for: .touchUpInside)
        addSubview(avoidCongestion)
        avoidCongestion.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.equalToSuperview().inset(CGFloat.GlobalItemSpacing)
            make.width.equalTo(singleWidth)
        }
        
        avoidCost = buttonForTitle(PTDashboardConfig.languageFunc(text: "route_plan2"))
        avoidCost.addTarget(self, action: #selector(self.avoidCostAction(sender:)), for: .touchUpInside)
        addSubview(avoidCost)
        avoidCost.snp.makeConstraints { make in
            make.left.equalTo(self.avoidCongestion.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }
        
        avoidHighway = buttonForTitle(PTDashboardConfig.languageFunc(text: "route_plan3"))
        avoidHighway.addTarget(self, action: #selector(self.avoidHighwayAction(sender:)), for: .touchUpInside)
        addSubview(avoidHighway)
        avoidHighway.snp.makeConstraints { make in
            make.left.equalTo(self.avoidCost.snp.right).offset(CGFloat.GlobalItemSpacing)
            make.top.bottom.width.equalTo(self.avoidCongestion)
        }

        prioritiseHighway = buttonForTitle(PTDashboardConfig.languageFunc(text: "route_plan4"))
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
        
        let nameAttNormal: ASAttributedString = """
                    \(wrap: .embedding("""
                    \(title,.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 10)))
                    """),.paragraph(.alignment(.left),.lineSpacing(1)))
                    """
        let nameAttSelected: ASAttributedString = """
                    \(wrap: .embedding("""
                    \(title,.foreground(PTDashboardConfig.shared.appMainColor),.font(.appfont(size: 10)))
                    """),.paragraph(.alignment(.left),.lineSpacing(1)))
                    """
        reBtn.layer.borderColor = UIColor.lightGray.cgColor
        reBtn.layer.borderWidth = 1.0
        reBtn.layer.cornerRadius = 5
        reBtn.titleLabel?.numberOfLines = 2
        reBtn.setAttributedTitle(nameAttNormal.value, for: .normal)
        reBtn.setAttributedTitle(nameAttSelected.value, for: .selected)
        return reBtn
    }
    
    private func changeButtonState(_ button: UIButton, selected: Bool) {
        button.isSelected = selected
        button.layer.borderColor = button.isSelected ? PTDashboardConfig.shared.appMainColor.cgColor : UIColor.lightGray.cgColor
    }
}

class PTMotoNavigationViewController: PTMotoBaseViewController {

    var routeIndicatorInfoArray = [RouteCollectionViewInfo]()

    var currentSpeedLimit:UInt8 = 0
    
    let homeSize:CGFloat = 44
    
    private lazy var amapNormalView:MAMapView = {
        let view = MAMapView()
        view.showsUserLocation = true
        view.userTrackingMode = .follow
        view.mapType = .standardNight
        view.delegate = self
        view.compassOrigin = .init(x: -(CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace), y: CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing * 2 + homeSize)
        return view
    }()

    private lazy var amapView:MAMapView = {
        let view = PTGlobalMapManager.shared.amapView
        view.delegate = self
        view.compassOrigin = .init(x: -(CGFloat.kSCREEN_WIDTH - PTAppBaseConfig.share.defaultViewSpace), y: CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing * 2 + homeSize)
        return view
    }()
    
    private lazy var search: AMapSearchAPI = {
        let view = AMapSearchAPI()
        view!.delegate = self
        return view!
    }()
    
    // MARK: - UI 组件
    private lazy var searchBar:PTSearchBar = {
        let view = PTSearchBar()
        view.searchPlaceholder = PTDashboardConfig.languageFunc(text: "search_placeholder")
        view.searchPlaceholderColor = .lightGray
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
        view.searchTextColor = PTDashboardConfig.shared.appMainColor
        view.bounds = .init(origin: .zero, size: .init(width: 100, height: PTAppBaseConfig.share.navBarButtonSize))
        return view
    }()
    
    private lazy var floatingToolbarBackground: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemThinMaterialDark)
        let view = UIVisualEffectView(effect: blurEffect)
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        // 增加精美的原生阴影
        view.layer.shadowColor = UIColor.clear.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowOpacity = 0.3
        view.layer.shadowRadius = 8
        view.layer.masksToBounds = false
        return view
    }()

    private lazy var toolbarStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        stack.alignment = .center
        stack.spacing = 2.5// 紧凑排列
        return stack
    }()

    private lazy var searchResultsTableView:UITableView = {
        let view = UITableView()
        view.delegate = self
        view.dataSource = self
        view.isHidden = true // 默认隐藏
        view.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9) // 半透明背景
        // Apple 风卡片
        view.layer.cornerRadius = 16
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowRadius = 10
        view.layer.shadowOffset = CGSize(width: 0, height: 5)
        return view
    }()
    private lazy var homeButton:PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setImage(UIImage(.house.fill), for: .normal)
        view.addActionHandlers(handler: { _ in
            self.routeToSavedLocation(key: "PT_HomeLocation")
        })
        view.bounds = .init(origin: .zero, size: .init(width: self.homeSize, height: self.homeSize))
        return view
    }()
    private lazy var officeButton:PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setImage(UIImage(.briefcase.fill), for: .normal)
        view.addActionHandlers(handler: { _ in
            self.routeToSavedLocation(key: "PT_OfficeLocation")
        })
        view.bounds = .init(origin: .zero, size: .init(width: self.homeSize, height: self.homeSize))
        return view
    }()
    private lazy var locationButton: PTBaseButton = {
        let view = PTBaseButton(type: .system)
        // 使用 SF Symbols 的定位图标
        view.setImage(UIImage(systemName: "location.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.addActionHandlers(handler: { [weak self] _ in
            self?.backToCurrentLocation()
        })
        view.bounds = .init(origin: .zero, size: .init(width: self.homeSize, height: self.homeSize))
        return view
    }()
    
    private lazy var globalMicStatusButton: PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setImage(UIImage(.mic.slashFill).withTintColor(.gray, renderingMode: .alwaysOriginal), for: .normal)
        view.bounds = .init(origin: .zero, size: .init(width: self.homeSize, height: self.homeSize))
        return view
    }()
    
    private func backToCurrentLocation() {
        // 确保我们有有效的坐标数据
        guard userCurrentLocation.latitude != 0, userCurrentLocation.longitude != 0 else {
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: Double(userCurrentLocation.latitude),
                                                longitude: Double(userCurrentLocation.longitude))
        
        // 方案 1：强制将地图模式切回跟随状态
        if amapView.userTrackingMode != .follow {
            amapView.setUserTrackingMode(.follow, animated: true)
        }
        // 方案 2：直接平滑移动地图中心并恢复合适的缩放级别
        amapView.setCenter(coordinate, animated: true)
        amapView.setZoomLevel(16.5, animated: true)
        
        // 给出轻微的触觉反馈，提升操作手感
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()
    }

    private lazy var startNavigationButton:UIButton = {
        let view = UIButton(type: .system)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setTitle("🚀", for: .normal)
        view.setTitle("🏍️", for: .disabled)
        view.titleLabel?.font = .appfont(size: 18)
        view.setBackgroundColor(color: PTDashboardConfig.shared.appMainColor, forState: .normal)
        view.setBackgroundColor(color: .systemGray, forState: .disabled)
        view.setTitleColor(.white, for: .normal)
        view.layer.cornerRadius = 12
        view.isHidden = true // 只有规划好路线才显示
        view.addActionHandlers(handler: { _ in
            self.navAction()
        })
        return view
    }()
    
    func navAction() {
        PTDashboardConfig.shared.naving = true
        self.startNavigationTapped()
        self.driveView.isHidden = false
        self.routePlantList.isHidden = true
        let annotationsToRemove = self.amapView.annotations.filter { annotation in
            if annotation is PTPeerAnnotation {
                return false
            }
            if let _ = PTMOTOParkingManager.shared.getLastParkedLocation() {
                if let naviAnno = annotation as? NaviPointAnnotation, naviAnno.naviPointType == .parking {
                    return false
                }
            }
            return true
        }
        self.amapView.removeAnnotations(annotationsToRemove)
        self.amapView.removeOverlays(self.amapView.overlays)
        if self.testButton.isSelected {
            AMapNaviDriveManager.sharedInstance().startEmulatorNavi()
        } else {
            AMapNaviDriveManager.sharedInstance().startGPSNavi()
        }
        if let _ = self.routeIndicatorInfoArray.first(where: { $0.isSelected }) {
            PTLiveActivityManager.shared.startNavigationActivity(destination: "目标地点", expectedArrival: Date())
        }
        NotificationCenter.default.post(name: PTCarPlayStarNavNotification, object: nil)
        
    }
        
    private var amapSearchResults:[MAPointAnnotation] = []
    
    // MARK: - 状态变量
    private var currentDestination: CLLocationCoordinate2D?
    private var currentRouteOverlay: MKPolyline?

    lazy var preferenceView: PreferenceView = {
        let view = PreferenceView()
        return view
    }()
    var isMultipleRoutePlan = true

    var loadCurrentLocation:Bool = false
    var currentCity:String = ""
    
    lazy var driveView: AMapNaviDriveView = {
        let view = PTGlobalMapManager.shared.driveView
        view.delegate = self
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
    
    let routePlantItemHeight:CGFloat = 64.adapter
    lazy var routePlantList:PTCollectionView = {
                                
        let collectionConfig = PTCollectionViewConfig()
        collectionConfig.viewType = .Custom
        collectionConfig.footerRefresh = false
        collectionConfig.topRefresh = false

        let view = PTCollectionView(viewConfig: collectionConfig)
        view.registerClassCells(classs: [PTRoutePlantCell.ID:PTRoutePlantCell.self])
        view.customerLayout = { sectionIndex,section in
            return UICollectionView.horizontalLayoutSystem(data: section.rows,itemOriginalX: PTAppBaseConfig.share.defaultViewSpace,itemWidth: 130.adapter,itemHeight: self.routePlantItemHeight,topContentSpace: CGFloat.GlobalItemSpacing,bottomContentSpace: CGFloat.GlobalItemSpacing,itemLeadingSpace: CGFloat.GlobalItemSpacing)
        }
        view.cellInCollection = { collectionView,sectionModel,indexPath in
            if let itemRow = sectionModel.rows?[indexPath.row] {
                let getCell = collectionView.dequeueReusableCell(withReuseIdentifier: itemRow.ID, for: indexPath)
                if let cell = getCell as? PTRoutePlantCell {
                    cell.info = self.routeIndicatorInfoArray[indexPath.row]
                    return cell
                }
            }
            return nil
        }
        view.collectionDidSelect = { collectionView,sectionModel,indexPath in
            for i in self.routeIndicatorInfoArray.indices {
                self.routeIndicatorInfoArray[i].isSelected = i == indexPath.row
            }
            self.routePlantList.reloadAllData() {
                PTGCDManager.shared.runOnMain(block: {
                    if let findModel = self.routeIndicatorInfoArray.first(where: { $0.isSelected}) {
                        PTDashboardConfig.shared.currentRouteDistance = findModel.distance
                        self.selectNaviRouteWithID(routeID: findModel.routeID)
                    }
                })
            }
        }
        view.isHidden = true
        return view
    }()

    lazy var muteButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.speaker.fill), for: .selected)
        view.setImage(UIImage(.speaker.slashFill), for: .normal)
        view.addActionHandlers(handler: { sender in
            sender.isSelected.toggle()
            PTMotoUserDefaultStruct.NavMute = !sender.isSelected
        })
        view.isSelected = !PTMotoUserDefaultStruct.NavMute
        view.bounds = .init(origin: .zero, size: .init(width: self.homeSize, height: self.homeSize))
        return view
    }()
    
    lazy var stopCarplyButton:PTBaseButton = {
        let view = PTBaseButton(type: .custom)
        view.setImage(UIImage(.stop.circleFill), for: .normal)
        view.addActionHandlers(handler: { sender in
            NotificationCenter.default.post(name: PTCarPlayStopNavNotification, object: nil)
            PTGCDManager.shared.delayOnMain(time: 0.3, block: {
                self.updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
            })
        })
        view.isEnabled = false
        view.bounds = .init(origin: .zero, size: .init(width: self.homeSize, height: self.homeSize))
        return view
    }()
    
    var isKeywordSearch:Bool = false
    
    private var peerAnnotations: [MCPeerID: PTPeerAnnotation] = [:]
    
    @MainActor deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setCustomTitleView(searchBar)
        setCustomRightButtons(buttons: [testButton])
                
        updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
        updateMicStatusUI(isRunning: PTLocalIntercomManager.shared.isRunning,
                          isHandsFree: PTLocalIntercomManager.shared.isHandsFreeMode,
                          isTalking: PTLocalIntercomManager.shared.isTalking,
                          otherMemberTalking:PTLocalIntercomManager.shared.otherMemberTalking)
        if PTDashboardConfig.shared.blueConnected {
            PTMOTOParkingManager.shared.clearParkingSpot()
            if let findValue = self.amapView.annotations.first(where: { $0 is NaviPointAnnotation }),let findRealValue = findValue as? NaviPointAnnotation,findRealValue.naviPointType == .parking {
                self.amapView.removeAnnotation(findRealValue)
            }
        }
    }
    
    func mapSet() {
        AMapNaviDriveManager.sharedInstance().delegate = nil
        AMapNaviDriveManager.sharedInstance().removeDataRepresentative(driveView)
        amapView.removeFromSuperview()
        driveView.removeFromSuperview()
        view.addSubview(amapNormalView)
        amapNormalView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        self.view.sendSubviewToBack(amapNormalView)
    }
    
    func navReset() {
        amapNormalView.removeFromSuperview()
        PTGlobalMapManager.shared.attachAMapView(to: self.view,delegate: self)
        self.view.sendSubviewToBack(amapView)
        amapView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        PTGlobalMapManager.shared.attachDriveView(to: self.view,delegate: self)
        // 确保 startNavigationButton 等在最上方
        driveView.snp.remakeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total)
            make.bottom.equalToSuperview().inset((CGFloat.GlobalItemSpacing + CGFloat.kTabbarHeight_Total))
        }
        
        self.view.bringSubviewToFront(self.startNavigationButton)
        if !PTDashboardConfig.shared.naving {
            self.startNavigationButton.isHidden = true
        }
        AMapNaviDriveManager.sharedInstance().delegate = self
        AMapNaviDriveManager.sharedInstance().allowsBackgroundLocationUpdates = true
        AMapNaviDriveManager.sharedInstance().pausesLocationUpdatesAutomatically = false
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(driveView)
        AMapNaviDriveManager.sharedInstance().addDataRepresentative(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupLocationManager()
        setupUI()
        //将driveView添加为导航数据的Representative，使其可以接收到导航诱导数据
        
        pt_observerLanguage {
            if self.vcDidLoad {
                self.searchBar.searchPlaceholder = PTDashboardConfig.languageFunc(text: "search_placeholder")
                self.amapView.mapLanguage = PTDashboardConfig.appIsInChinese() ? 0 : 1
                self.amapView.mapType = .standardNight
            }
        }
        vcDidLoad = true
        
        motoParkingLocation()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleEmergencyNavigation(_:)), name: MotorcycleStartRealNavigation, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePositionNavigation(_:)), name: MotorcycleSearchAndNavigate, object: nil)
        
        updateMapModeForCarPlayConnection(isActive: PTCarPlayManager.isCarPlayActive)
        
        NotificationCenter.default.addObserver(self, selector: #selector(carplayIsInBackground), name: PTCarPlayDidEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(carplayIsNotInBackground), name: PTCarPlayDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleIntercomStatusChange(_:)), name: PTIntercomGlobalStatusChanged, object: nil)
        
        NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { [weak self] notification in
            if let scene = notification.object as? UIScene, scene.session.role == .carTemplateApplication {
                PTNSLogConsole("🔗 CarPlay 刚刚连接！让手机界面做出反应")
                self?.updateMapModeForCarPlayConnection(isActive: true)
            }
        }
        
        NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] notification in
            if let scene = notification.object as? UIScene, scene.session.role == .carTemplateApplication {
                PTNSLogConsole("🔌 CarPlay 刚刚断开！恢复手机界面")
                self?.updateMapModeForCarPlayConnection(isActive: false)
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handlePeerLocationUpdate(_:)), name: PTPeerLocationDidUpdateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePeerLeave(_:)), name: PTPeerDidLeaveNetworkNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePeerAvatarUpdate(_:)), name: PTPeerAvatarDidUpdateNotification, object: nil)
        
        updateMicStatusUI(isRunning: PTLocalIntercomManager.shared.isRunning,
                          isHandsFree: PTLocalIntercomManager.shared.isHandsFreeMode,
                          isTalking: PTLocalIntercomManager.shared.isTalking,
                          otherMemberTalking:PTLocalIntercomManager.shared.otherMemberTalking)
        
        PTGCDManager.shared.delayOnMain(time: 0.55) {
            let flag = AMapLocationDataAvailableForCoordinate(PTLocationEngine.shared.lastLocation?.coordinate ?? .init(latitude: 0, longitude: 0))
            self.amapNormalView.mapLanguage = flag ? 0 : 1
            self.amapNormalView.mapType = .standardNight
            self.amapView.mapLanguage = flag ? 0 : 1
            self.amapView.mapType = .standardNight
        }
    }
    
    @objc private func handlePeerAvatarUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let peerID = userInfo["peerID"] as? MCPeerID,
              let avatarImage = userInfo["avatarImage"] as? UIImage else { return }
        
        // 找到该队友在地图上的数据模型
        if let existingAnno = peerAnnotations[peerID] {
            // 存入数据模型，防止滑出屏幕后复用丢失
            existingAnno.avatarImage = avatarImage
            
            // 立即刷新地图上正在显示的 View
            if let annoView = amapView.view(for: existingAnno) {
                DispatchQueue.main.async {
                    // 使用切圆工具处理后贴到大头针上
                    annoView.image = avatarImage.pt_toMapCircleAvatar()
                }
            }
        }
    }

    @objc private func handleIntercomStatusChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let isRunning = userInfo["isRunning"] as? Bool,
              let isHandsFree = userInfo["isHandsFree"] as? Bool,
              let isTalking = userInfo["isTalking"] as? Bool,
              let otherMemberTalking = userInfo["otherMemberTalking"] as? Bool else { return }
        
        updateMicStatusUI(isRunning: isRunning, isHandsFree: isHandsFree, isTalking: isTalking,otherMemberTalking:otherMemberTalking)
    }
    
    private func updateMicStatusUI(isRunning: Bool, isHandsFree: Bool, isTalking: Bool,otherMemberTalking:Bool) {
        guard isRunning else {
            // 未开启状态 -> 灰色斜杠麦克风，没有任何动画
            globalMicStatusButton.setImage(UIImage(systemName: "mic.slash.fill")?.withTintColor(.darkGray, renderingMode: .alwaysOriginal), for: .normal)
            UIView.animate(withDuration: 0.2) {
                self.globalMicStatusButton.transform = .identity
            }
            return
        }

        // 我自己正在讲话 (主动发送)
        if isTalking {
            // 醒目的绿色麦克风
            globalMicStatusButton.setImage(UIImage(systemName: "mic.fill")?.withTintColor(.systemGreen, renderingMode: .alwaysOriginal), for: .normal)
            
            // 放大 1.2 倍，提示正在强力收音
            UIView.animate(withDuration: 0.2, animations: {
                self.globalMicStatusButton.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            })
            return // 命中此状态后直接返回，拦截后续判断
        }
        
        // 我自己没说，但是队友正在讲话 (被动接收)
        if otherMemberTalking {
            // 将图标变成代表发声的“喇叭”，并使用代表安全的蓝色（与绿色的发送区分开）
            // 注: PooTools 或 SwifterSwift 里的系统图标调用方式如果不同，请替换为对应的枚举，如 .speakerWave2Fill
            globalMicStatusButton.setImage(UIImage(systemName: "speaker.wave.2.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal), for: .normal)
            
            // 轻微放大 1.1 倍，表示当前通道有声音在活动
            UIView.animate(withDuration: 0.2, animations: {
                self.globalMicStatusButton.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            })
            return
        }
        
        // 全频道安静，处于待机状态
        // 恢复图标原始大小
        UIView.animate(withDuration: 0.2, animations: {
            self.globalMicStatusButton.transform = .identity
        })
        
        if isHandsFree {
            // 待机 + 免提模式 -> 橙色麦克风，代表时刻保持监听
            globalMicStatusButton.setImage(UIImage(systemName: "mic.fill")?.withTintColor(.systemOrange, renderingMode: .alwaysOriginal), for: .normal)
        } else {
            // 待机 + 普通按键模式 -> 白色斜杠麦克风，代表通道闭锁
            globalMicStatusButton.setImage(UIImage(systemName: "mic.slash.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        }
    }

    func carplayIsInBackground() {
        updateMapModeForCarPlayConnection(isActive: false)
    }
    
    func carplayIsNotInBackground() {
        updateMapModeForCarPlayConnection(isActive: true)
    }
    
    private func updateMapModeForCarPlayConnection(isActive: Bool) {
        if isActive {
            if PTDashboardConfig.shared.naving {
                mapSet()
                stopCarplyButton.isEnabled = true
            } else {
                navReset()
                stopCarplyButton.isEnabled = false
            }
        } else {
            navReset()
            stopCarplyButton.isEnabled = false
        }
    }
    
    @objc private func handlePositionNavigation(_ notification: Notification) {
        if let keyword = notification.object as? String,!keyword.isEmpty {
            self.isKeywordSearch = true
            self.amapSearchResults.removeAll()
            let request = AMapPOIKeywordsSearchRequest()
            request.keywords = keyword
            request.showFieldsType = .all
            search.aMapPOIKeywordsSearch(request)
        }
    }
    
    @objc private func handleEmergencyNavigation(_ notification: Notification) {
        guard let dict = notification.object as? [String: Any],
              let coordinate = dict["coordinate"] as? CLLocationCoordinate2D,
              let title = dict["title"] as? String else { return }
        
        // 1. 如果用户原本没在导航界面，可以将界面自动跳出来 (取决于你的产品设计)
        // 2. 调用我们之前写好的路线规划
        planRoute(to: coordinate, title: title)
        setPointPin(location: coordinate)
        
        // 3. (可选体验优化) 可以稍微延迟 1.5 秒等高德算好路，自动调用 startNavigationTapped()
        // 这样骑手连屏幕都不用点，算好路直接进入仪表盘逐向导航模式！
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.startNavigationButton.isEnabled { // 代表算路成功
                self.startNavigationButton.sendActions(for: .touchUpInside)
            }
        }
    }

    // MARK: - 初始化配置
    private func setupLocationManager() {
        PTLocationEngine.shared.switchEngineMode(to: .riding)
        if !PTLocationEngine.shared.isTracking {
            PTLocationEngine.shared.startTracking()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleLocationUpdate(_:)), name: PTLocationEngineDidUpdate, object: nil)
    }
        
    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData,
              let coordinate = tripData.currentLocation else { return }
        
        self.userCurrentLocation = AMapNaviPoint.location(withLatitude: coordinate.coordinate.latitude, longitude: coordinate.coordinate.longitude)!
        
        // 🚨 核心修复 2：发起请求前，立刻将标记设为 true，打破无限网络请求的死循环！
        if !self.loadCurrentLocation {
            self.loadCurrentLocation = true
            
            let regeo = AMapReGeocodeSearchRequest()
            regeo.location = AMapGeoPoint.location(withLatitude: coordinate.coordinate.latitude, longitude: coordinate.coordinate.longitude)
            regeo.requireExtension = true
            self.search.aMapReGoecodeSearch(regeo)
        }
    }

    // MARK: - UI 布局实现
    private func setupUI() {
        NotificationCenter.default.addObserver(self, selector: #selector(dashBoardReload), name: MotorcycleDashBoardChange, object: nil)

        view.addSubview(floatingToolbarBackground)
        floatingToolbarBackground.contentView.addSubview(toolbarStack)
        toolbarStack.addArrangedSubview(homeButton)
        toolbarStack.addArrangedSubview(officeButton)
        toolbarStack.addArrangedSubview(muteButton)
        toolbarStack.addArrangedSubview(stopCarplyButton)
        toolbarStack.addArrangedSubview(locationButton)
        toolbarStack.addArrangedSubview(globalMicStatusButton)

        floatingToolbarBackground.snp.makeConstraints { make in
            make.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.width.equalTo(self.homeSize)
            // 高度由内部 StackView 撑开
        }
        
        toolbarStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        for btn in toolbarStack.arrangedSubviews {
            btn.snp.makeConstraints { make in
                make.size.equalTo(btn.bounds.size)
            }
        }

        view.addSubviews([preferenceView,searchResultsTableView,startNavigationButton,routePlantList])
        
        preferenceView.snp.makeConstraints { make in
            make.top.equalTo(self.floatingToolbarBackground)
            make.height.equalTo(self.homeSize)
            make.left.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.right.equalTo(self.floatingToolbarBackground.snp.left).offset(-CGFloat.GlobalItemSpacing)
        }

        searchResultsTableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
            make.top.equalToSuperview().inset(CGFloat.kNavBarHeight_Total + CGFloat.GlobalItemSpacing)
            make.height.equalTo(300.adapter)
        }
        
        startNavigationButton.snp.makeConstraints { make in
            make.bottom.equalToSuperview().inset(CGFloat.kTabbarHeight_Total + CGFloat.GlobalItemSpacing)
            make.height.equalTo(50)
            make.left.right.equalToSuperview().inset(PTAppBaseConfig.share.defaultViewSpace)
        }
        
        routePlantList.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(self.startNavigationButton.snp.top).offset(-CGFloat.GlobalItemSpacing)
            make.height.equalTo(self.routePlantItemHeight + CGFloat.GlobalItemSpacing * 2)
        }
    }
    
    func listSet(finishTask:PTCollectionCallback? = nil) {
        var sections = [PTSection]()
        let rowsTrip = routeIndicatorInfoArray.map { value in
            let row = PTRows(ID:PTRoutePlantCell.ID)
            return row
        }
        let sectionTrip = PTSection(rows: rowsTrip)
        sections.append(sectionTrip)
        routePlantList.showCollectionDetail(collectionData: sections,finishTask: finishTask)
    }
        
    @objc private func startNavigationTapped() {
        
        // 可以在这里收起按钮，或者进入纯粹的导航视角
        startNavigationButton.isEnabled = false
        startNavigationButton.isHidden = true
    }
    
    var userCurrentLocation = AMapNaviPoint.location(withLatitude: 0, longitude: 0)!
    
    // MARK: - 路线规划与绘制
    private func planRoute(to destination: CLLocationCoordinate2D, title: String) {
        currentDestination = destination
        guard userCurrentLocation.latitude != 0, userCurrentLocation.longitude != 0 else {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "alert_title"))
            return
        }
        PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "alert_loading"))
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
        
        let name = key.contains("Home") ? "🏠" : "🏢"
        let alert = UIAlertController(title: PTDashboardConfig.languageFunc(text: "set_success"), message: PTDashboardConfig.language(key: "address_set_success", name), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
        present(alert, animated: true)
    }
    
    private func routeToSavedLocation(key: String) {
        searchBar.resignFirstResponder()
        searchResultsTableView.isHidden = true
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Double],
              let lat = dict["lat"], let lon = dict["lon"] else {
            let alert = UIAlertController(title: PTDashboardConfig.languageFunc(text: "alert_title"), message: PTDashboardConfig.languageFunc(text: "address_empty"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_confirm"), style: .default))
            present(alert, animated: true)
            return
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let name = key.contains("Home") ? "🏠" : "🏢"
        planRoute(to: coordinate, title: name)
        setPointPin(location: coordinate)
    }
    
    @objc func dashBoardReload() {
        self.searchBar.cursorColor = PTDashboardConfig.shared.appMainColor
    }
    
    override func handleMotorcycleDisconnect() {
        super.handleMotorcycleDisconnect()
        motoParkingLocation()
    }
    
    func motoParkingLocation() {
        if let findParking = PTMOTOParkingManager.shared.getLastParkedLocation() {
            if let findValue = self.amapView.annotations.first(where: { $0 is NaviPointAnnotation }),let findRealValue = findValue as? NaviPointAnnotation,findRealValue.naviPointType == .parking {
                self.amapView.removeAnnotation(findRealValue)
            }
            
            let beginAnnotation = NaviPointAnnotation()
            beginAnnotation.coordinate = CLLocationCoordinate2D(latitude: Double(findParking.latitude), longitude: Double(findParking.longitude))
            beginAnnotation.title = PTDashboardConfig.languageFunc(text: "pin_parking")
            beginAnnotation.naviPointType = .parking
            amapView.addAnnotation(beginAnnotation)
            
            amapView.setZoomLevel(17.5, animated: true)
        } else {
            self.amapView.removeAnnotations(self.amapView.annotations)
        }
        
        driveViewCloseButtonClicked(self.driveView)
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
        let actionSheet = UIAlertController(title: completion.title, message: PTDashboardConfig.languageFunc(text: "address_option"), preferredStyle: .actionSheet)
        
        // 选项 1: 规划路线
        actionSheet.addAction(UIAlertAction(title: "📍", style: .default) { [weak self] _ in
            self?.performSearchAndRoute(completion: completion)
        })
        
        // 选项 2: 设为家
        actionSheet.addAction(UIAlertAction(title: "🏠", style: .default) { [weak self] _ in
            self?.performSearchAndSave(completion: completion, key: "PT_HomeLocation")
        })
        
        // 选项 3: 设为公司
        actionSheet.addAction(UIAlertAction(title: "🏢", style: .default) { [weak self] _ in
            self?.performSearchAndSave(completion: completion, key: "PT_OfficeLocation")
        })
        
        actionSheet.addAction(UIAlertAction(title: PTDashboardConfig.languageFunc(text: "button_cancel"), style: .cancel))
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
        let annotationsToRemove = self.amapView.annotations.filter { annotation in
            if annotation is PTPeerAnnotation {
                return false
            }
            if let _ = PTMOTOParkingManager.shared.getLastParkedLocation() {
                if let naviAnno = annotation as? NaviPointAnnotation, naviAnno.naviPointType == .parking {
                    return false
                }
            }
            return true
        }
        self.amapView.removeAnnotations(annotationsToRemove)

        let beginAnnotation = NaviPointAnnotation()
        beginAnnotation.coordinate = CLLocationCoordinate2D(latitude: Double(userCurrentLocation.latitude), longitude: Double(userCurrentLocation.longitude))
        beginAnnotation.title = PTDashboardConfig.languageFunc(text: "address_start")
        beginAnnotation.naviPointType = .start
        
        amapView.addAnnotation(beginAnnotation)
        
        let endAnnotation = NaviPointAnnotation()
        endAnnotation.coordinate = location
        endAnnotation.title = PTDashboardConfig.languageFunc(text: "address_end")
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
    
    func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
        
        // 过滤我们自定义的导航大头针
        if let peerAnno = annotation as? PTPeerAnnotation {
            let identifier = "PTPeerAnnotationView"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if view == nil {
                view = MAAnnotationView(annotation: peerAnno, reuseIdentifier: identifier)
                view?.canShowCallout = true
            }
            
            view?.annotation = peerAnno

            if let customAvatar = peerAnno.avatarImage {
                view?.image = customAvatar.pt_toMapCircleAvatar()
            } else {
                // 没收到头像前，用默认图标兜底
                view?.image = UIImage(named: "placeholder")?.pt_toMapCircleAvatar()
            }

            // 保证刚添加上来时，车头方向也是对的
            view?.transform = CGAffineTransform(rotationAngle: CGFloat(peerAnno.course * .pi / 180.0))
            return view
        }

        if let naviAnno = annotation as? NaviPointAnnotation {
            switch naviAnno.naviPointType {
            case .parking:
                let parkID = "PTMOTOParkingAnotationView"
                var pointAnnotationView = mapView.dequeueReusableAnnotationView(withIdentifier: parkID) as? PTMOTOParkingAnotationView
                
                if pointAnnotationView == nil {
                    pointAnnotationView = PTMOTOParkingAnotationView(annotation: naviAnno, reuseIdentifier: parkID)
                }
                pointAnnotationView?.image = PTLocalIntercomManager.shared.currentMyAvatar().pt_toMapCircleAvatar()
                pointAnnotationView?.canShowCallout = true
                pointAnnotationView?.isDraggable = false
                return pointAnnotationView
            default:
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
                } else if naviAnno.naviPointType == .parking {
                    pointAnnotationView?.pinColor = .purple
                }
                
                return pointAnnotationView
            }
        }
        return nil
    }
    
    func mapView(_ mapView: MAMapView!, didAnnotationViewCalloutTapped view: MAAnnotationView!) {
        switch view.reuseIdentifier {
        case "PTMOTOParkingAnotationView":
            self.planRoute(to: view.annotation.coordinate, title: view.annotation.title ?? "")
            setPointPin(location: view.annotation.coordinate)
        default:
            break
        }
    }
    
    func mapView(_ mapView: MAMapView!, didLongPressedAt coordinate: CLLocationCoordinate2D) {
        planRoute(to: coordinate, title: "")
        setPointPin(location: coordinate)
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
        amapSearchResults.removeAll()
        searchResultsTableView.reloadData()
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
        
        if !isKeywordSearch {
            if !self.amapSearchResults.isEmpty {
                searchResultsTableView.isHidden = false
                searchResultsTableView.reloadData()
                self.searchBar.text = ""
            } else {
                searchResultsTableView.isHidden = true
                searchResultsTableView.reloadData()
            }
        } else {
            if let first = self.amapSearchResults.first {
                self.planRoute(to: first.coordinate, title: first.title)
                setPointPin(location: first.coordinate)
            }
        }
    }
    
    func onReGeocodeSearchDone(_ request: AMapReGeocodeSearchRequest!, response: AMapReGeocodeSearchResponse!) {
        currentCity = response.regeocode.addressComponent.city
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
            let title = String(format: "Plant:%d", preferenceView.strategy(isMultiple: isMultipleRoutePlan).rawValue)
            let subtitle = String(format: "Distance:%dKm | Time:%@", aRoute.routeLength / 1000, aRoute.routeTime.timeString)
            let info = RouteCollectionViewInfo(routeID: Int( truncating: aNumber), title: title, subTitle: subtitle,isSelected: false,distance: Double(aRoute.routeLength / 1000))
            routeIndicatorInfoArray.append(info)
        }
        
        amapView.showAnnotations(amapView.annotations, animated: false)
        
        if let first = routeIndicatorInfoArray.first {
            PTDashboardConfig.shared.currentRouteDistance = first.distance
            routeIndicatorInfoArray[0].isSelected = true
            if !isKeywordSearch {
                self.routePlantList.isHidden = false
                self.routePlantList.clearAllData { _ in
                    self.listSet()
                }
            }
            selectNaviRouteWithID(routeID: first.routeID)
        }
    }
    
    func selectNaviRouteWithID(routeID: Int) {
        //在开始导航前进行路径选择
        if AMapNaviDriveManager.sharedInstance().selectNaviRoute(withRouteID: routeID) {
            selecteOverlayWithRouteID(routeID: routeID)
        } else {
            PTProgressHUD.show(text: PTDashboardConfig.languageFunc(text: "alert_title"))
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
        
        if isKeywordSearch {
            self.navAction()
            isKeywordSearch.toggle()
        }
    }
        
    func driveManager(onArrivedDestination driveManager: AMapNaviDriveManager) {
        self.driveViewCloseButtonClicked(self.driveView)
    }
    
    func driveManagerDidEndEmulatorNavi(_ driveManager: AMapNaviDriveManager) {
        self.driveViewCloseButtonClicked(self.driveView)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, error: Error) {
        let error = error as NSError
        PTNSLogConsole("error:{%d - %@}", error.code, error.localizedDescription)
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteFailure error: Error) {
        let error = error as NSError
        PTNSLogConsole("CalculateRouteFailure:{%d - %@}", error.code, error.localizedDescription)
    }

//    func driveManager(onCalculateRouteSuccess driveManager: AMapNaviDriveManager) {
//        //算路成功后显示路径
//    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, postRouteNotification notifyData: AMapNaviRouteNotifyData) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>\(String(describing: notifyData.roadName))")
    }
            
    func driveManager(_ manager: AMapNaviDriveManager?, onUpdateNaviSpeedLimitSection speed: Int) {
        PTNSLogConsole(">>>>>>>>>>>>>>>>>>>>>>>>>>>>\(speed)")
        self.currentSpeedLimit = UInt8(speed)
    }
    
    func driveManagerIsNaviSoundPlaying(_ driveManager: AMapNaviDriveManager) -> Bool {
        return SpeechSynthesizer.Shared.isSpeaking()
    }
    
    func driveManager(_ driveManager: AMapNaviDriveManager, playNaviSound soundString: String, soundStringType: AMapNaviSoundType) {
        if muteButton.isSelected {
            SpeechSynthesizer.Shared.speak(soundString)
        }
    }
            
    func driveManager(_ driveManager: AMapNaviDriveManager, onCalculateRouteSuccessWith type: AMapNaviRoutePlanType) {
        showNaviRoutes()
        PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Rerouting...", title: "",nextManeuver: PTManeuverMap.rerouting)
    }
        
    func driveManager(_ driveManager: AMapNaviDriveManager, update gpsSignalStrength: AMapNaviGPSSignalStrength) {
        switch gpsSignalStrength {
        case .smartPos:
            break
        default:
            PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Searching GPS...", title: "",nextManeuver: PTManeuverMap.noGPS)
        }
    }
}

extension PTMotoNavigationViewController : AMapNaviDriveViewDelegate {
        
    func driveViewCloseButtonClicked(_ driveView: AMapNaviDriveView) {
        PTDashboardConfig.shared.naving = false
        //停止导航
        AMapNaviDriveManager.sharedInstance().stopNavi()
        AMapNaviDriveManager.sharedInstance().removeDataRepresentative(driveView)
        self.driveView.isHidden = true
        self.startNavigationButton.isHidden = true
        self.startNavigationButton.isEnabled = false
        let annotationsToRemove = self.amapView.annotations.filter { annotation in
            if annotation is PTPeerAnnotation {
                return false
            }
            if let _ = PTMOTOParkingManager.shared.getLastParkedLocation() {
                if let naviAnno = annotation as? NaviPointAnnotation, naviAnno.naviPointType == .parking {
                    return false
                }
            }
            return true
        }
        self.amapView.removeAnnotations(annotationsToRemove)
        self.amapView.removeOverlays(amapView.overlays)
        //停止语音
        if muteButton.isSelected {
            SpeechSynthesizer.Shared.stopSpeak()
        }
        PTBluetoothServerManager.shared.sendWelcomeMessage(next: "Yeah!!!!!!!!!!", title: "Navigation finished!!!!!!!!!!!!!!!!!!!!")
        PTLiveActivityManager.shared.stopNavigationActivity()
    }
    
    func driveView(_ view: AMapNaviDriveView, didChangeTo state: AMapNaviDriveViewState) { }
}

extension PTMotoNavigationViewController:AMapNaviDriveDataRepresentable {
         
    func driveManager(_ driveManager: AMapNaviDriveManager, updateCruiseElecCameraInfos cameraInfos: [AMapNaviTrafficFacilityInfo]) {
        if let firstCamera = cameraInfos.first {
            // cameraSpeed 通常代表该路段限速，为 0 时表示无限速或未知
            if firstCamera.limitSpeed > 0 {
                self.currentSpeedLimit = UInt8(firstCamera.limitSpeed)
            }
        }
    }
    
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
        PTNSLogConsole("\(naviInfo)")
        PTMotoDashBoardNavFunction.sendNavDataToDashboard(naviInfo: naviInfo, currentSpeedLimit: self.currentSpeedLimit)
    }
}

//MARK: MultipeerConnectivity
extension PTMotoNavigationViewController {
    // MARK: - 队友地图位置更新逻辑
    @objc private func handlePeerLocationUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let peerID = userInfo["peerID"] as? MCPeerID,
              let location = userInfo["location"] as? PTPeerLocation else { return }
        
        let coordinate = CLLocationCoordinate2D(latitude: location.lat, longitude: location.lon)
        
        // 1. 如果队友已经在地图上了 -> 平滑更新位置和方向
        if let existingAnno = peerAnnotations[peerID] {
            // 高德地图支持直接修改 coordinate，大头针会自动平移
            existingAnno.coordinate = coordinate
            existingAnno.course = location.course
            
            // 找到对应的 View 并旋转它指向正确的车头方向
            if let annoView = amapView.view(for: existingAnno) {
                UIView.animate(withDuration: 0.3) {
                    // 将角度转换为弧度进行旋转
                    annoView.transform = CGAffineTransform(rotationAngle: CGFloat(location.course * .pi / 180.0))
                }
            }
        }
        // 2. 如果是新队友 -> 创建大头针并添加到地图
        else {
            let newAnno = PTPeerAnnotation()
            newAnno.peerID = peerID
            newAnno.coordinate = coordinate
            newAnno.course = location.course
            newAnno.title = peerID.displayName
            
            peerAnnotations[peerID] = newAnno
            amapView.addAnnotation(newAnno)
        }
    }

    @objc private func handlePeerLeave(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let peerID = userInfo["peerID"] as? MCPeerID else { return }
        
        // 队友掉线，从地图和字典中抹除他
        if let existingAnno = peerAnnotations[peerID] {
            amapView.removeAnnotation(existingAnno)
            peerAnnotations.removeValue(forKey: peerID)
        }
    }
}
