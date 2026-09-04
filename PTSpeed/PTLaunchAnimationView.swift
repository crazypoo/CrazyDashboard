//
// PTLaunchAnimationView.swift
// PTSpeed
//
// EN: A short, native launch transition that matches the static launch screen.
// ES: Una transición de arranque breve y nativa que coincide con la pantalla estática.
// 中文：一个与静态启动页首帧一致的原生短启动过渡动画。
//

import UIKit
import PooTools

// EN: The presenter is main-actor isolated because it owns scene windows and UIKit views.
// ES: El presentador está aislado en el actor principal porque controla ventanas y vistas UIKit.
// 中文：展示器隔离在主 actor 上，因为它负责场景窗口和 UIKit 视图。
@MainActor
enum PTLaunchAnimationPresenter {

    private static let overlayTag = 208_041
    private static var hasPresentedInProcess = false

    static func present(in scene: UIWindowScene) {
        guard !hasPresentedInProcess,
              let window = window(in: scene),
              window.viewWithTag(overlayTag) == nil else {
            return
        }

        hasPresentedInProcess = true

        let overlay = PTLaunchAnimationView(frame: window.bounds)
        overlay.tag = overlayTag
        overlay.accessibilityIdentifier = "launch.animation.overlay"
        overlay.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: window.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])
        window.layoutIfNeeded()
        overlay.start()
    }

    static func bringToFrontIfVisible(in scene: UIWindowScene) {
        guard let window = window(in: scene),
              let overlay = window.viewWithTag(overlayTag) else {
            return
        }
        window.bringSubviewToFront(overlay)
    }

    static func dismiss(in scene: UIWindowScene) {
        guard let window = window(in: scene),
              let overlay = window.viewWithTag(overlayTag) as? PTLaunchAnimationView else {
            return
        }
        overlay.dismissImmediately()
    }

    private static func window(in scene: UIWindowScene) -> UIWindow? {
        PTSceneContext.activeWindow(in: scene)
    }
}

@MainActor
private final class PTLaunchAnimationView: UIView {

    private let logoView = UIImageView(image: UIImage(named: "launch_peugeot_shield"))
    private let accentView = UIView()
    private let shineLayer = CAGradientLayer()
    private let shineMaskLayer = CALayer()

    private var accentWidthConstraint: NSLayoutConstraint?
    private var watchdogTask: Task<Void, Never>?
    private var hasStarted = false
    private var hasFinished = false

    private let backgroundColorValue = UIColor(red: 11.0 / 255.0,
                                                green: 13.0 / 255.0,
                                                blue: 16.0 / 255.0,
                                                alpha: 1.0)
    private let accentColor = UIColor(red: 1.0,
                                      green: 122.0 / 255.0,
                                      blue: 0.0,
                                      alpha: 1.0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shineLayer.frame = logoView.bounds
        shineMaskLayer.frame = shineLayer.bounds
        shineMaskLayer.contents = logoView.image?.cgImage
        shineMaskLayer.contentsGravity = .resizeAspect
        shineLayer.mask = shineMaskLayer
        CATransaction.commit()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        layoutIfNeeded()
        scheduleWatchdog()

        if UIAccessibility.isReduceMotionEnabled {
            startReducedMotion()
        } else {
            startFullMotion()
        }
    }

    func dismissImmediately() {
        finishImmediately()
    }

    private func configureView() {
        // EN: Keep this overlay visually identical to the static launch storyboard.
        // ES: Mantén esta capa visualmente idéntica al storyboard estático de arranque.
        // 中文：让这个覆盖层与静态启动 storyboard 保持完全一致。
        backgroundColor = backgroundColorValue
        isOpaque = true
        isUserInteractionEnabled = true
        isAccessibilityElement = false

        logoView.translatesAutoresizingMaskIntoConstraints = false
        logoView.contentMode = .scaleAspectFit
        logoView.isAccessibilityElement = false
        logoView.layer.minificationFilter = .trilinear
        logoView.alpha = 0.72
        logoView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        addSubview(logoView)

        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.backgroundColor = accentColor
        accentView.layer.cornerRadius = 1.0
        accentView.layer.shadowColor = accentColor.cgColor
        accentView.layer.shadowOpacity = 0.45
        accentView.layer.shadowRadius = 5.0
        accentView.layer.shadowOffset = .zero
        accentView.alpha = 0.45
        accentView.transform = CGAffineTransform(scaleX: 0.35, y: 1.0)
        addSubview(accentView)

        accentWidthConstraint = accentView.widthAnchor.constraint(equalToConstant: 28.0)
        NSLayoutConstraint.activate([
            logoView.centerXAnchor.constraint(equalTo: centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10.0),
            logoView.widthAnchor.constraint(equalToConstant: 132.0),
            logoView.heightAnchor.constraint(equalToConstant: 132.0),
            accentView.centerXAnchor.constraint(equalTo: logoView.centerXAnchor),
            accentView.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 14.0),
            accentView.heightAnchor.constraint(equalToConstant: 2.0),
            accentWidthConstraint!
        ])

        shineLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.78).cgColor,
            UIColor.clear.cgColor
        ]
        shineLayer.locations = [-0.35, -0.25, -0.15]
        shineLayer.startPoint = CGPoint(x: 0.0, y: 0.5)
        shineLayer.endPoint = CGPoint(x: 1.0, y: 0.5)
        shineLayer.opacity = 1.0
        logoView.layer.addSublayer(shineLayer)
    }

    private func startFullMotion() {
        let sweep = CABasicAnimation(keyPath: "locations")
        sweep.fromValue = [-0.35, -0.25, -0.15]
        sweep.toValue = [1.15, 1.25, 1.35]
        sweep.beginTime = CACurrentMediaTime() + 0.18
        sweep.duration = 0.52
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shineLayer.add(sweep, forKey: "metallicSweep")

        UIView.animateKeyframes(withDuration: 1.0,
                                delay: 0.0,
                                options: [.calculationModeCubic, .beginFromCurrentState]) { [weak self] in
            guard let self else { return }

            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.24) {
                self.logoView.alpha = 1.0
                self.logoView.transform = .identity
            }

            UIView.addKeyframe(withRelativeStartTime: 0.18, relativeDuration: 0.48) {
                self.accentWidthConstraint?.constant = 76.0
                self.accentView.alpha = 1.0
                self.accentView.transform = .identity
                self.layoutIfNeeded()
            }

            UIView.addKeyframe(withRelativeStartTime: 0.76, relativeDuration: 0.24) {
                self.alpha = 0.0
            }
        } completion: { [weak self] _ in
            PTMainActorBridge.perform { [weak self] in
                self?.finishImmediately()
            }
        }
    }

    private func startReducedMotion() {
        UIView.animate(withDuration: 0.2,
                       delay: 0.0,
                       options: [.curveEaseOut, .beginFromCurrentState]) { [weak self] in
            self?.alpha = 0.0
        } completion: { [weak self] _ in
            PTMainActorBridge.perform { [weak self] in
                self?.finishImmediately()
            }
        }
    }

    private func scheduleWatchdog() {
        watchdogTask = PTMainActorBridge.after(1.5) { [weak self] in
            self?.finishImmediately()
        }
    }

    private func finishImmediately() {
        guard !hasFinished else { return }
        hasFinished = true
        watchdogTask?.cancel()
        watchdogTask = nil
        layer.removeAllAnimations()
        removeFromSuperview()
    }
}
