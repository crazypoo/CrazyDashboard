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

        let bodyColor = configuration.model == .xp400GT
            ? UIColor(red: 0.10, green: 0.28, blue: 0.65, alpha: 1)
            : UIColor(red: 0.18, green: 0.24, blue: 0.38, alpha: 1)
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
}
