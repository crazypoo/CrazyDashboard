//
//  PTVehicleTwin3DAsset.swift
//  CrazyDashboard
//
//  EN: Original procedural low-poly XP400 / XP400 GT asset pack for SceneKit.
//  ES: Paquete original procedural de baja poligonización para XP400 / XP400 GT en SceneKit.
//  中文：面向 SceneKit 的原创 XP400 / XP400 GT 程序化低面数资源包。
//

import SceneKit
import UIKit

enum PTVehicleTwin3DNodeName {
    static let root = "xp400.root"
    static let body = "xp400.body"
    static let frontWheel = "xp400.frontWheel.pivot"
    static let rearWheel = "xp400.rearWheel.pivot"
    static let headlight = "xp400.light.headlight"
    static let brakeLight = "xp400.light.brake"
    static let indicatorLeft = "xp400.light.indicator.left"
    static let indicatorRight = "xp400.light.indicator.right"
    static let kickstand = "xp400.kickstand.pivot"
    static let rpmIndicator = "xp400.rpm.indicator"
    static let gVector = "xp400.motion.gVector"

    static let required: [String] = [
        root,
        body,
        frontWheel,
        rearWheel,
        headlight,
        brakeLight,
        indicatorLeft,
        indicatorRight,
        kickstand,
        rpmIndicator,
        gVector
    ]
}

struct PTVehicleTwin3DAssetManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let source: String
    let coordinateSystem: String
    let modelNames: [String]
    let requiredNodeNames: [String]
    let wheelRadiusMeters: Double
    let maximumTriangleCount: Int
    let maximumMaterialCount: Int
    let usesExternalTextures: Bool
}

@MainActor
final class PTVehicleTwin3DNodeReferences {
    let root: SCNNode
    let body: SCNNode
    let frontWheel: SCNNode
    let rearWheel: SCNNode
    let headlight: SCNNode
    let brakeLight: SCNNode
    let indicatorLeft: SCNNode
    let indicatorRight: SCNNode
    let kickstand: SCNNode
    let rpmIndicator: SCNNode
    let gVector: SCNNode

    init(
        root: SCNNode,
        body: SCNNode,
        frontWheel: SCNNode,
        rearWheel: SCNNode,
        headlight: SCNNode,
        brakeLight: SCNNode,
        indicatorLeft: SCNNode,
        indicatorRight: SCNNode,
        kickstand: SCNNode,
        rpmIndicator: SCNNode,
        gVector: SCNNode
    ) {
        self.root = root
        self.body = body
        self.frontWheel = frontWheel
        self.rearWheel = rearWheel
        self.headlight = headlight
        self.brakeLight = brakeLight
        self.indicatorLeft = indicatorLeft
        self.indicatorRight = indicatorRight
        self.kickstand = kickstand
        self.rpmIndicator = rpmIndicator
        self.gVector = gVector
    }
}

@MainActor
enum PTVehicleTwin3DAssetFactory {
    static func makeScene(
        configuration: PTVehicleTwinConfiguration
    ) -> (scene: SCNScene, nodes: PTVehicleTwin3DNodeReferences) {
        let scene = SCNScene()
        let root = SCNNode()
        root.name = PTVehicleTwin3DNodeName.root
        scene.rootNode.addChildNode(root)

        // EN: Match the active procedural 3D palette to the XP400 2D layers; GT stays a future variant.
        // ES: Alinea la paleta 3D procedural activa con las capas 2D de XP400; GT queda como variante futura.
        // 中文：让当前程序化 3D 配色与 XP400 2D 分层保持一致；GT 仅保留为未来变体。
        let bodyColor = configuration.model == .xp400GT
            ? UIColor(red: 0.10, green: 0.28, blue: 0.65, alpha: 1)
            : UIColor(red: 0.10, green: 0.24, blue: 0.56, alpha: 1)
        let body = makeBody(color: bodyColor)
        body.name = PTVehicleTwin3DNodeName.body
        root.addChildNode(body)

        let rearWheel = makeWheel(name: PTVehicleTwin3DNodeName.rearWheel)
        rearWheel.position = SCNVector3(-0.98, 0.38, 0)
        root.addChildNode(rearWheel)

        let frontWheel = makeWheel(name: PTVehicleTwin3DNodeName.frontWheel)
        frontWheel.position = SCNVector3(1.03, 0.38, 0)
        root.addChildNode(frontWheel)

        let headlight = makeLamp(
            name: PTVehicleTwin3DNodeName.headlight,
            color: .systemYellow,
            radius: 0.11
        )
        headlight.position = SCNVector3(1.18, 0.87, -0.01)
        root.addChildNode(headlight)

        let brakeLight = makeLamp(
            name: PTVehicleTwin3DNodeName.brakeLight,
            color: .systemRed,
            radius: 0.08
        )
        brakeLight.position = SCNVector3(-1.15, 0.86, -0.01)
        root.addChildNode(brakeLight)

        let indicatorLeft = makeLamp(
            name: PTVehicleTwin3DNodeName.indicatorLeft,
            color: .systemOrange,
            radius: 0.065
        )
        indicatorLeft.position = SCNVector3(0.98, 0.87, 0.36)
        root.addChildNode(indicatorLeft)

        let indicatorRight = makeLamp(
            name: PTVehicleTwin3DNodeName.indicatorRight,
            color: .systemOrange,
            radius: 0.065
        )
        indicatorRight.position = SCNVector3(0.98, 0.87, -0.36)
        root.addChildNode(indicatorRight)

        let kickstand = makeKickstand()
        kickstand.name = PTVehicleTwin3DNodeName.kickstand
        kickstand.position = SCNVector3(-0.34, 0.56, 0.27)
        root.addChildNode(kickstand)

        let rpmIndicator = makeRPMIndicator()
        rpmIndicator.name = PTVehicleTwin3DNodeName.rpmIndicator
        rpmIndicator.position = SCNVector3(0.42, 1.02, -0.39)
        root.addChildNode(rpmIndicator)

        let gVector = makeGVector()
        gVector.name = PTVehicleTwin3DNodeName.gVector
        gVector.position = SCNVector3(0, 1.52, 0)
        root.addChildNode(gVector)

        return (
            scene,
            PTVehicleTwin3DNodeReferences(
                root: root,
                body: body,
                frontWheel: frontWheel,
                rearWheel: rearWheel,
                headlight: headlight,
                brakeLight: brakeLight,
                indicatorLeft: indicatorLeft,
                indicatorRight: indicatorRight,
                kickstand: kickstand,
                rpmIndicator: rpmIndicator,
                gVector: gVector
            )
        )
    }

    private static func makeBody(color: UIColor) -> SCNNode {
        let body = SCNNode()

        // EN: Keep the low-poly silhouette recognizably XP400: tall screen, angular fairing, long seat and footboard.
        // ES: Mantiene la silueta low-poly reconocible como XP400: pantalla alta, carenado angular, asiento largo y plataforma.
        // 中文：保持低面数模型具备 XP400 的辨识度：高风挡、棱角前脸、长座垫和踏板。

        let mainGeometry = SCNBox(width: 1.88, height: 0.50, length: 0.68, chamferRadius: 0.12)
        mainGeometry.firstMaterial = material(color: color)
        let main = SCNNode(geometry: mainGeometry)
        main.position = SCNVector3(-0.04, 0.83, 0)
        body.addChildNode(main)

        let fairingGeometry = SCNBox(width: 0.78, height: 0.56, length: 0.76, chamferRadius: 0.16)
        fairingGeometry.firstMaterial = material(color: color.withAlphaComponent(0.90))
        let fairing = SCNNode(geometry: fairingGeometry)
        fairing.position = SCNVector3(0.78, 0.88, 0)
        fairing.eulerAngles.z = -0.10
        body.addChildNode(fairing)

        let seatGeometry = SCNBox(width: 0.88, height: 0.10, length: 0.60, chamferRadius: 0.05)
        seatGeometry.firstMaterial = material(color: UIColor(white: 0.06, alpha: 1))
        let seat = SCNNode(geometry: seatGeometry)
        seat.position = SCNVector3(-0.34, 1.16, 0)
        body.addChildNode(seat)

        let screenGeometry = SCNBox(width: 0.24, height: 0.28, length: 0.52, chamferRadius: 0.04)
        screenGeometry.firstMaterial = material(color: UIColor(white: 0.04, alpha: 1))
        let screen = SCNNode(geometry: screenGeometry)
        screen.position = SCNVector3(0.38, 1.22, 0)
        screen.eulerAngles.z = -0.18
        body.addChildNode(screen)

        let windshieldGeometry = SCNBox(width: 0.42, height: 0.52, length: 0.66, chamferRadius: 0.05)
        windshieldGeometry.firstMaterial = transparentMaterial(color: UIColor(red: 0.28, green: 0.42, blue: 0.50, alpha: 0.42))
        let windshield = SCNNode(geometry: windshieldGeometry)
        windshield.position = SCNVector3(0.67, 1.48, 0)
        windshield.eulerAngles.z = -0.20
        body.addChildNode(windshield)

        let footboardGeometry = SCNBox(width: 1.08, height: 0.08, length: 0.86, chamferRadius: 0.03)
        footboardGeometry.firstMaterial = material(color: UIColor(white: 0.22, alpha: 1))
        let footboard = SCNNode(geometry: footboardGeometry)
        footboard.position = SCNVector3(-0.02, 0.62, 0)
        body.addChildNode(footboard)

        let frontPanelGeometry = SCNBox(width: 0.54, height: 0.44, length: 0.80, chamferRadius: 0.12)
        frontPanelGeometry.firstMaterial = material(color: color.withAlphaComponent(0.92))
        let frontPanel = SCNNode(geometry: frontPanelGeometry)
        frontPanel.position = SCNVector3(0.80, 1.00, 0)
        frontPanel.eulerAngles.z = -0.14
        body.addChildNode(frontPanel)

        let forkMaterial = material(color: UIColor(red: 0.72, green: 0.52, blue: 0.18, alpha: 1))
        for z: Float in [-0.23, 0.23] {
            let forkGeometry = SCNCylinder(radius: 0.035, height: 0.64)
            forkGeometry.firstMaterial = forkMaterial
            let fork = SCNNode(geometry: forkGeometry)
            fork.position = SCNVector3(0.98, 0.60, z)
            fork.eulerAngles.z = -0.14
            body.addChildNode(fork)
        }

        let exhaustGeometry = SCNCylinder(radius: 0.07, height: 0.58)
        exhaustGeometry.firstMaterial = material(color: UIColor(white: 0.30, alpha: 1))
        let exhaust = SCNNode(geometry: exhaustGeometry)
        exhaust.position = SCNVector3(-0.72, 0.60, 0.38)
        exhaust.eulerAngles.z = Float.pi / 2
        body.addChildNode(exhaust)

        let handlebarGeometry = SCNCylinder(radius: 0.035, height: 0.86)
        handlebarGeometry.firstMaterial = material(color: UIColor(white: 0.55, alpha: 1))
        let handlebar = SCNNode(geometry: handlebarGeometry)
        handlebar.position = SCNVector3(0.54, 1.39, 0)
        handlebar.eulerAngles.z = Float.pi / 2
        body.addChildNode(handlebar)

        return body
    }

    private static func makeWheel(name: String) -> SCNNode {
        let wheel = SCNNode()
        wheel.name = name
        wheel.eulerAngles.x = Float.pi / 2

        let tireGeometry = SCNCylinder(radius: 0.34, height: 0.16)
        tireGeometry.radialSegmentCount = 12
        tireGeometry.firstMaterial = material(color: UIColor(white: 0.04, alpha: 1))
        wheel.addChildNode(SCNNode(geometry: tireGeometry))

        let rimGeometry = SCNTorus(ringRadius: 0.19, pipeRadius: 0.025)
        rimGeometry.ringSegmentCount = 12
        rimGeometry.pipeSegmentCount = 6
        rimGeometry.firstMaterial = material(color: UIColor(white: 0.60, alpha: 1))
        wheel.addChildNode(SCNNode(geometry: rimGeometry))

        // EN: Three crossing bars form an XP400-style cross-spoke wheel and rotate with the wheel pivot.
        // ES: Tres barras cruzadas forman una rueda de radios cruzados estilo XP400 y giran con el pivote.
        // 中文：用三根交叉轮辐表现 XP400 风格的交叉辐条，并随车轮枢轴旋转。
        for angle in stride(from: Float(0), to: Float.pi, by: Float.pi / 3) {
            let spokeGeometry = SCNCylinder(radius: 0.012, height: 0.52)
            spokeGeometry.firstMaterial = material(color: UIColor(white: 0.78, alpha: 1))
            let spoke = SCNNode(geometry: spokeGeometry)
            spoke.eulerAngles.z = angle
            wheel.addChildNode(spoke)
        }

        let hubGeometry = SCNCylinder(radius: 0.07, height: 0.18)
        hubGeometry.firstMaterial = material(color: UIColor(white: 0.78, alpha: 1))
        wheel.addChildNode(SCNNode(geometry: hubGeometry))

        return wheel
    }

    private static func makeLamp(name: String, color: UIColor, radius: CGFloat) -> SCNNode {
        let geometry = SCNSphere(radius: radius)
        geometry.segmentCount = 8
        geometry.firstMaterial = material(color: color.withAlphaComponent(0.35), emission: color)
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.opacity = 0.25
        return node
    }

    private static func makeKickstand() -> SCNNode {
        let pivot = SCNNode()
        let geometry = SCNCapsule(capRadius: 0.035, height: 0.54)
        geometry.capSegmentCount = 4
        geometry.radialSegmentCount = 6
        geometry.firstMaterial = material(color: UIColor(white: 0.72, alpha: 1))
        let leg = SCNNode(geometry: geometry)
        leg.position = SCNVector3(0, -0.28, 0)
        leg.eulerAngles.z = -0.18
        pivot.addChildNode(leg)
        return pivot
    }

    private static func makeRPMIndicator() -> SCNNode {
        let geometry = SCNTorus(ringRadius: 0.13, pipeRadius: 0.018)
        geometry.ringSegmentCount = 12
        geometry.pipeSegmentCount = 5
        geometry.firstMaterial = material(color: .systemGreen, emission: .systemGreen)
        let node = SCNNode(geometry: geometry)
        node.eulerAngles.x = Float.pi / 2
        node.opacity = 0.3
        return node
    }

    private static func makeGVector() -> SCNNode {
        let root = SCNNode()
        let shaftGeometry = SCNCylinder(radius: 0.025, height: 0.28)
        shaftGeometry.firstMaterial = material(color: .systemOrange, emission: .systemOrange)
        let shaft = SCNNode(geometry: shaftGeometry)
        shaft.position = SCNVector3(0, 0.14, 0)
        root.addChildNode(shaft)

        let tipGeometry = SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.14)
        tipGeometry.firstMaterial = material(color: .systemOrange, emission: .systemOrange)
        let tip = SCNNode(geometry: tipGeometry)
        tip.position = SCNVector3(0, 0.33, 0)
        root.addChildNode(tip)
        root.opacity = 0.25
        return root
    }

    private static func material(color: UIColor, emission: UIColor? = nil) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor(white: 0.25, alpha: 1)
        if let emission {
            material.emission.contents = emission
        }
        return material
    }

    private static func transparentMaterial(color: UIColor) -> SCNMaterial {
        let material = material(color: color)
        material.transparency = 0.72
        material.isDoubleSided = true
        return material
    }
}
