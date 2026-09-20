//
//  PTDashBoardView.swift
//  CrazyDashboard
//
//  Created by 邓杰豪 on 28/7/2026.
//

import UIKit
import CoreLocation
import PooTools
import SwifterSwift
import SnapKit
import SafeSFSymbols

@MainActor
class PTDashBoardView: UIView, PTVehicleTelemetryConsumer {
    
    let lrSpacing: CGFloat = 44
    let topSpacing: CGFloat = 44
    let bottomSpacing: CGFloat = CGFloat.kTabbarSaveAreaHeight + 44
    
    // MARK: - UI 组件声明
    lazy var speedometer: PTSpeedometerView = {
        let view = PTSpeedometerView()
        view.progressColor = PTDashboardConfig.shared.appMainColor
        view.needleColor = PTDashboardConfig.shared.appMainColor
        view.maxSpeed = PTDashboardConfig.shared.appUniIsMetric ? 180 : 110
        view.unitLabel.text = PTDashboardConfig.shared.appShowUniLabel
        view.direction = .clockwise
        view.tickStep = 10
        view.majorTickStep = 30
        return view
    }()
    
    let musicNowPlaying = PTNowPlayingView(frame: .zero)
    let compassRoller = PTCompassRollerView(frame: .zero)
    let leanAngleGauge = PTLeanAngleView()
    let mapView = PTMapView(frame: .zero)
    let tripStatsView = PTTripStatsView(frame: .zero)
    let gForceView = PTGForceView(frame: .zero)
    let crashOverlay = PTCrashWarningView()
    let bumpMeter = PTBumpMeterView()
    let pitchGauge = PTPitchView()
    private var lastUnifiedSpeedKmh: Double?
    private let ghostLiveStore = PTRideGhostLiveStore()
    private let dashboardContextEngine = PTDashboardContextEngine.shared
    private let dashboardThemeEngine = PTDashboardThemeEngine.shared
    private let contextOverlay = PTDashboardContextOverlay()
    private let ghostStatusLabel = UILabel()
    private var latestCoordinate: CLLocationCoordinate2D?
    private var latestTelemetrySnapshot = PTUnifiedVehicleTelemetrySnapshot.empty
    
    lazy var lightControl: PTIndicatorPanel = {
        let view = PTIndicatorPanel()
        view.isHidden = !PTDashboardConfig.shared.blueConnected
        return view
    }()
    
    private lazy var resetMotionButton: PTBaseButton = {
        let view = PTBaseButton(type: .system)
        view.setImage(UIImage(.figure.walkMotion).withTintColor(.white, renderingMode: .alwaysOriginal), for: .normal)
        view.addActionHandlers(handler: { _ in
            PTMotion.shared.calibrateZeroPoint()
            PTMotion.shared.resetLeanAngles()
        })
        return view
    }()

    // MARK: - 生命周期
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupDashboardUI()
        
        PTTripManager.shared.liveStatsBlock = { [weak self] tripStats in
            self?.tripStatsView.updateStats(with: tripStats)
        }
        ghostLiveStore.onChange = { [weak self] snapshot in
            self?.renderGhostStatus(snapshot)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDashboardContextChange(_:)),
            name: PTDashboardContextEngine.didChange,
            object: dashboardContextEngine
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDashboardThemeChange(_:)),
            name: PTDashboardThemeEngine.didChange,
            object: dashboardThemeEngine
        )
        startPootoolsEngines()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let liveStore = ghostLiveStore
        let contextEngine = dashboardContextEngine
        let themeEngine = dashboardThemeEngine
        NotificationCenter.default.removeObserver(self)
        Task { @MainActor in
            liveStore.stop()
            contextEngine.stop()
            themeEngine.stop()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 当系统计算完真实的 AutoLayout bounds 后，这里会被自动调用。
        // 无论屏幕如何旋转、如何缩放，圆角永远是绝对精准的圆形。
        let speedRadius = speedometer.bounds.size.height / 2
        if speedRadius > 0 {
            speedometer.layer.cornerRadius = speedRadius
            speedometer.clipsToBounds = true
        }
        
        let musicRadius = musicNowPlaying.bounds.size.height / 2
        if musicRadius > 0 {
            musicNowPlaying.layer.cornerRadius = musicRadius
            musicNowPlaying.clipsToBounds = true
        }
    }
    
    // MARK: - 数据绑定
    func motionSet(motionData: PTMotionData) {
        guard PTVehicleTelemetryBridge.shared.mode == .live else { return }
        self.speedometer.updateEnvironment(altitude: nil, pressureKpa: motionData.pressure)
        self.gForceView.updateGForce(x: motionData.gForceX, y: motionData.gForceY)
        self.leanAngleGauge.updateLean(current: motionData.roll, leftMax: motionData.maxLeftLean, rightMax: motionData.maxRightLean)
        self.bumpMeter.updateBump(zForce: motionData.gForceZ)
        self.pitchGauge.updatePitch(degrees: motionData.pitch)
        
        // 处理机车事故警报 UI
        showEmergencyOverlay(motionData.isTipOverDetected)
        dashboardContextEngine.updateMotion(
            speedKmh: PTMotion.shared.currentSpeedKmh,
            warningActive: motionData.isTipOverDetected
        )
    }
        
    @objc private func handleLocationUpdate(_ notification: Notification) {
        guard let tripData = notification.object as? PTTripData else { return }
        guard PTVehicleTelemetryBridge.shared.mode == .live else { return }

        latestCoordinate = tripData.currentLocation?.coordinate
        updateLiveGhost(timestamp: tripData.currentLocation?.timestamp ?? Date())

        // EN: Location updates only drive heading and environment; speed is rendered by the unified resolver.
        // ES: Las actualizaciones de ubicación solo alimentan rumbo y entorno; la velocidad la renderiza el resolvedor unificado.
        // 中文：定位更新只负责航向和环境数据，车速统一由 Resolver 渲染。
        self.compassRoller.updateHeading(tripData.courseDegree)
        self.speedometer.updateEnvironment(altitude: tripData.altitude, pressureKpa: nil)
    }

    func vehicleTelemetryDidUpdate(_ snapshot: PTUnifiedVehicleTelemetrySnapshot) {
        latestTelemetrySnapshot = snapshot
        applyUnifiedTelemetry(PTVehicleTelemetryProjections.dashboard(from: snapshot))
        if let location = snapshot.location {
            latestCoordinate = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )
            updateLiveGhost(timestamp: snapshot.updatedAt)
        }
    }

    private func applyUnifiedTelemetry(_ projection: PTDashboardProjection) {
        if let speed = projection.speedKmh {
            lastUnifiedSpeedKmh = speed
            speedometer.updateSpeed(
                CGFloat(PTDashboardConfig.shared.appShowMileage(speed)),
                animated: projection.snapshot.mode == .live
            )
        } else if lastUnifiedSpeedKmh != nil {
            // EN: Remove an expired speed instead of leaving the last source on screen.
            // ES: Elimina una velocidad caducada en vez de dejar visible la última fuente.
            // 中文：速度过期后清除旧值，避免界面继续显示上一个来源的数据。
            lastUnifiedSpeedKmh = nil
            speedometer.updateSpeed(0, animated: false)
        }
        if let lean = projection.double(for: .lean) {
            leanAngleGauge.updateLean(
                current: lean,
                leftMax: lean < 0 ? abs(lean) : 0,
                rightMax: lean > 0 ? lean : 0
            )
        }
        if let gForceX = projection.double(for: .gForceX),
           let gForceY = projection.double(for: .gForceY) {
            gForceView.updateGForce(x: gForceX, y: gForceY)
        }
        if let gForceZ = projection.double(for: .gForceZ) {
            bumpMeter.updateBump(zForce: gForceZ)
        }
        if let pitch = projection.double(for: .pitch) {
            pitchGauge.updatePitch(degrees: pitch)
        }
    }

    // MARK: - UI 排版
    private func setupDashboardUI() {
        ghostStatusLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        ghostStatusLabel.textColor = .systemOrange
        ghostStatusLabel.textAlignment = .center
        ghostStatusLabel.numberOfLines = 1
        ghostStatusLabel.adjustsFontSizeToFitWidth = true
        ghostStatusLabel.isHidden = true
        ghostStatusLabel.accessibilityHint = PTRideGhostCopy.text(.fallback)
        
        // 1. 底层：地图
        // 2. 中层：各种仪表盘
        // 3. 顶层：警告图层
        self.addSubviews([mapView,
                          speedometer, musicNowPlaying, leanAngleGauge, compassRoller,
                          tripStatsView, gForceView,resetMotionButton, bumpMeter, pitchGauge, lightControl,
                          contextOverlay, crashOverlay, ghostStatusLabel])
        
        // --- 1. 背景层 ---
        mapView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(10)
            make.width.equalToSuperview().multipliedBy(0.85)
            make.centerX.equalToSuperview()
        }
        
        // --- 2. 左右主力表盘 ---
        speedometer.snp.makeConstraints { make in
            make.top.equalTo(self.mapView).offset(44)
            make.bottom.equalTo(self.mapView).offset(-64)
            make.width.equalTo(speedometer.snp.height) // 保持 1:1 正圆形
            make.left.equalToSuperview().inset(CGFloat.GlobalItemSpacing / 2)
        }
        
        musicNowPlaying.snp.makeConstraints { make in
            make.top.bottom.width.equalTo(speedometer)
            make.right.equalToSuperview().inset(CGFloat.GlobalItemSpacing / 2)
        }

        // --- 3. 顶部信息栏 ---
        tripStatsView.snp.makeConstraints { make in
            make.top.equalTo(self.mapView)
            make.left.equalTo(self.speedometer.snp.centerX).offset(20)
            make.right.equalTo(self.musicNowPlaying.snp.centerX).offset(-20)
            make.height.equalTo(72)
        }

        ghostStatusLabel.snp.makeConstraints { make in
            make.top.equalTo(tripStatsView.snp.bottom).offset(2)
            make.left.right.equalTo(compassRoller)
            make.height.equalTo(18)
        }

        contextOverlay.snp.makeConstraints { make in
            make.top.equalTo(mapView).offset(10)
            make.left.right.equalToSuperview().inset(18)
            make.height.equalTo(48)
        }
        
        gForceView.snp.makeConstraints { make in
            make.right.equalTo(self.musicNowPlaying)
            make.top.equalTo(self.mapView)
            make.width.height.equalTo(64)
        }
        
        resetMotionButton.snp.makeConstraints { make in
            make.right.equalTo(self.gForceView)
            make.top.equalTo(self.gForceView.snp.bottom).offset(CGFloat.GlobalItemSpacing)
            make.size.equalTo(PTAppBaseConfig.share.navBarButtonSize)
        }
        
        // --- 4. 中轴线组件 (由下至上堆叠) ---
        // 压弯倾角仪
        leanAngleGauge.snp.makeConstraints { make in
            make.bottom.equalTo(self.mapView)
            make.left.equalTo(speedometer.snp.right).offset(10)
            make.right.equalTo(musicNowPlaying.snp.left).offset(-10)
            make.height.equalTo(35)
        }
        
        // 罗盘
        compassRoller.snp.makeConstraints { make in
            make.left.right.equalTo(leanAngleGauge)
            make.bottom.equalTo(self.leanAngleGauge.snp.top)
            make.height.equalTo(54)
        }
        
        // 颠簸仪
        bumpMeter.snp.makeConstraints { make in
            make.left.right.equalTo(compassRoller)
            make.bottom.equalTo(compassRoller.snp.top)
            make.height.equalTo(20)
        }

        // --- 5. 底部两侧组件 ---
        pitchGauge.snp.makeConstraints { make in
            make.right.equalTo(gForceView)
            make.bottom.equalTo(self.mapView)
            make.height.equalTo(64)
            make.left.greaterThanOrEqualTo(compassRoller.snp.right).offset(CGFloat.GlobalItemSpacing) // 🌟 优化：使用柔性约束，防止与中央罗盘重叠
            make.centerX.equalTo(self.musicNowPlaying)
        }
        
        lightControl.snp.makeConstraints { make in
            make.height.bottom.equalTo(self.pitchGauge)
            make.left.equalTo(self.speedometer)
            make.right.lessThanOrEqualTo(compassRoller.snp.left).offset(-CGFloat.GlobalItemSpacing) // 🌟 优化：使用柔性约束
            make.centerX.equalTo(self.speedometer)

        }
        
        // --- 6. 顶层事故警报 ---
        crashOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        crashOverlay.isHidden = true
    }
    
    // MARK: - 引擎管理
    @MainActor private func startPootoolsEngines() {
        let telemetryBridge = PTVehicleTelemetryBridge.shared
        telemetryBridge.startIfNeeded()
        PTVehicleTelemetryConsumerHub.shared.register(self)
        let connectivity = PTVehicleConnectivityCoordinator.shared
        telemetryBridge.ingest(
            legacySnapshot: connectivity.telemetrySnapshot,
            connectionSnapshot: connectivity.snapshot
        )

        PTLocationUsageCoordinator.shared.acquire(.dashboard)
        if !PTDashboardConfig.shared.blueConnected {
            PTMotion.shared.calibrateZeroPoint()
            PTTripManager.shared.handleConnect()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(handleLocationUpdate(_:)), name: PTLocationEngineDidUpdate, object: nil)
        PTMotion.shared.addDelegate(self)
        
        PTBluetoothServerManager.shared.addDelegate(self)
        dashboardContextEngine.start()
        dashboardThemeEngine.start()
        renderDashboardContext(dashboardContextEngine.snapshot)
        renderDashboardTheme(dashboardThemeEngine.tokens)
        ghostLiveStore.start()
    }
        
    private func showEmergencyOverlay(_ show: Bool) {
        // 防止重复触发动画，影响性能
        guard crashOverlay.isHidden == show else { return }
        
        UIView.transition(with: crashOverlay, duration: 0.3, options: .transitionCrossDissolve, animations: {
            self.crashOverlay.isHidden = !show
        }, completion: nil)
    }
    
    @objc func handleAuthSuccess() {
        PTDashboardConfig.shared.blueConnected = true
        lightControl.isHidden = false
        speedometer.playStartupSweep(duration: 1.5)
        PTMOTOParkingManager.shared.clearParkingSpot()
        dashboardContextEngine.refresh()
    }
    
    @objc func handleMotorcycleDisconnect() {
        lastUnifiedSpeedKmh = nil
        speedometer.resetToZeroWithAnimation()
        ghostStatusLabel.isHidden = true
        ghostLiveStore.stop()
        dashboardContextEngine.refresh()
    }

    @objc private func handleDashboardContextChange(_ notification: Notification) {
        guard let snapshot = notification.userInfo?["snapshot"] as? PTDashboardContextSnapshot else { return }
        renderDashboardContext(snapshot)
    }

    @objc private func handleDashboardThemeChange(_ notification: Notification) {
        guard let tokens = notification.userInfo?["tokens"] as? PTDashboardThemeTokens else { return }
        renderDashboardTheme(tokens)
    }

    // EN: The Dashboard adapter touches only decorative surfaces; map and safety indicators keep their semantics.
    // ES: El adaptador del tablero solo toca superficies decorativas; el mapa y los indicadores de seguridad conservan su semántica.
    // 中文：Dashboard 适配层只修改装饰表面，地图和安全指示器保持原有语义。
    private func renderDashboardTheme(_ tokens: PTDashboardThemeTokens) {
        backgroundColor = tokens.backgroundColor
        musicNowPlaying.applyDashboardTheme(tokens)
    }

    // EN: Existing cards stay in place; the context only changes emphasis and interruption level.
    // ES: Las tarjetas existentes permanecen en su sitio; el contexto solo cambia el énfasis y el nivel de interrupción.
    // 中文：现有卡片位置保持不变，上下文只调整强调程度和打扰级别。
    private func renderDashboardContext(_ snapshot: PTDashboardContextSnapshot) {
        contextOverlay.render(snapshot)

        let speedPolicy = snapshot.presentation(for: .speedRPM)
        speedometer.alpha = speedPolicy.isEmphasized ? 1 : 0.92

        let mediaPolicy = snapshot.presentation(for: .media)
        musicNowPlaying.isHidden = !mediaPolicy.isVisible
        // EN: Keep the card opacity stable; context changes must not look like a blink.
        // ES: Mantén estable la opacidad; los cambios de contexto no deben parecer un parpadeo.
        // 中文：保持卡片透明度稳定，避免上下文变化看起来像闪烁。
        musicNowPlaying.alpha = 0.82
        musicNowPlaying.isUserInteractionEnabled = mediaPolicy.isVisible

        let navigationPolicy = snapshot.presentation(for: .navigation)
        mapView.alpha = navigationPolicy.isEmphasized ? 1 : 0.96

        if snapshot.primaryContext == .warning {
            ghostStatusLabel.isHidden = true
        }
    }

    // EN: The live Ghost is informational only and disappears when route overlap is not proven.
    // ES: El Ghost en vivo es solo informativo y desaparece cuando no se prueba la superposición.
    // 中文：实时 Ghost 仅用于信息展示，未确认路线重叠时立即隐藏。
    private func updateLiveGhost(timestamp: Date) {
        guard PTTripManager.shared.isRecordingRide,
              let coordinate = latestCoordinate else {
            ghostStatusLabel.isHidden = true
            return
        }
        ghostLiveStore.update(
            coordinate: coordinate,
            speedKmh: latestTelemetrySnapshot.speedKmh ?? PTMotion.shared.currentSpeedKmh,
            rpm: latestTelemetrySnapshot.rpm ?? 0,
            timestamp: timestamp
        )
    }

    private func renderGhostStatus(_ snapshot: PTRideGhostLiveSnapshot) {
        guard PTTripManager.shared.isRecordingRide else {
            ghostStatusLabel.isHidden = true
            return
        }
        switch snapshot.availability {
        case .ready:
            let progress = Int(((snapshot.routeProgress ?? 0) * 100).rounded())
            let delta = snapshot.timeDeltaSeconds ?? 0
            let speed = snapshot.speedDeltaKmh ?? 0
            var statusParts = [
                "👻 \(PTRideGhostCopy.text(.live))",
                "\(PTRideGhostCopy.text(.progress)) \(progress)%",
                "\(PTRideGhostCopy.text(.timeDelta)) \(String(format: "%+.1fs", delta))",
                "Δ \(String(format: "%+.0f km/h", speed))",
                "\(PTRideGhostCopy.text(.historicalRPM)) \(snapshot.historicalRPM ?? 0)"
            ]
            if let roadQuality = snapshot.historicalRoadQuality,
               roadQuality != .unknown {
                statusParts.append(PTRideGhostCopy.roadSurfaceText(roadQuality))
            }
            ghostStatusLabel.text = statusParts.joined(separator: " · ")
            ghostStatusLabel.textColor = .systemGreen
            ghostStatusLabel.isHidden = false
        case .outsideOverlap:
            ghostStatusLabel.text = PTRideGhostCopy.text(.outsideOverlap)
            ghostStatusLabel.textColor = .systemOrange
            ghostStatusLabel.isHidden = false
        default:
            ghostStatusLabel.isHidden = true
        }
    }
}

extension PTDashBoardView : PTMotionDelegate {
    func motionManager(_ manager: PTMotion, didUpdateData data: PTMotionData) {
        self.motionSet(motionData: data)
    }
}

extension PTDashBoardView:PTBLEDashboardDelegate {
    func dashboardManager(_ manager: PTBluetoothServerManager, didChangeConnectionState isConnected: Bool) {
        if isConnected {
            handleAuthSuccess()
        } else {
            handleMotorcycleDisconnect()
        }
    }
}
