import SwiftUI

#if os(iOS)
import ARKit
@preconcurrency import SceneKit
import UIKit

struct ARMeasureView: UIViewRepresentable {
    let controller: MeasureController
    var onPhotoCaptured: ((UIImage) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller, onPhotoCaptured: onPhotoCaptured) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true

        context.coordinator.sceneView = view
        // Defer AR session start so the view renders a frame first
        DispatchQueue.main.async {
            context.coordinator.startSession()
        }
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.syncNodes()
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        // Pausing the ARSession can block the main thread, do it detached
        Task.detached(priority: .background) {
            uiView.session.pause()
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private let controller: MeasureController
        private let onPhotoCaptured: ((UIImage) -> Void)?
        weak var sceneView: ARSCNView?

        private var crosshairNode: SCNNode?
        private var liveLineNode: SCNNode?
        private var liveLabelNode: SCNNode?
        private var liveStartDotNode: SCNNode?
        private var segmentNodes: [UUID: (line: SCNNode, label: SCNNode, startDot: SCNNode, endDot: SCNNode)] = [:]
        // Area visualization
        private var closingPreviewLineNode: SCNNode?
        private var snapIndicatorNode: SCNNode?
        private var finalizedAreaNodeGroups: [UUID: (fill: SCNNode, label: SCNNode)] = [:]
        private var photoCaptureObserver: NSObjectProtocol?

        init(controller: MeasureController, onPhotoCaptured: ((UIImage) -> Void)?) {
            self.controller = controller
            self.onPhotoCaptured = onPhotoCaptured
            super.init()

            photoCaptureObserver = NotificationCenter.default.addObserver(
                forName: .capturePhoto,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    self?.capturePhoto()
                }
            }
        }

        deinit {
            if let observer = photoCaptureObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func startSession() {
            guard ARWorldTrackingConfiguration.isSupported, let sceneView else {
                controller.instructionText = "AR ist auf diesem Gerät nicht verfügbar."
                return
            }
            
            // Move AR configuration and session run to background to avoid main thread freeze
            Task.detached(priority: .userInitiated) {
                let config = ARWorldTrackingConfiguration()
                config.planeDetection = [.horizontal, .vertical]
                
                // Running the session takes a considerable lock internally so we do it detached
                sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                
                await MainActor.run {
                    self.prewarmShaders()
                }
            }
        }

        func capturePhoto() {
            guard let sceneView else { return }
            let image = sceneView.snapshot()
            onPhotoCaptured?(image)
        }

        private func prewarmShaders() {
            guard let sceneView else { return }
            let warmColor = UIColor.white.withAlphaComponent(0.02)

            let torus = SCNTorus(ringRadius: 0.012, pipeRadius: 0.001)
            torus.firstMaterial?.diffuse.contents = warmColor
            torus.firstMaterial?.lightingModel = .constant
            let torusNode = SCNNode(geometry: torus)

            let sphere = SCNSphere(radius: 0.004)
            sphere.firstMaterial?.diffuse.contents = warmColor
            sphere.firstMaterial?.lightingModel = .constant
            let sphereNode = SCNNode(geometry: sphere)

            let cyl = SCNCylinder(radius: 0.001, height: 0.01)
            cyl.firstMaterial?.diffuse.contents = warmColor
            cyl.firstMaterial?.lightingModel = .constant
            let cylNode = SCNNode(geometry: cyl)

            let text = SCNText(string: "12.5 cm", extrusionDepth: 0)
            text.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            text.flatness = 0.3
            text.firstMaterial?.diffuse.contents = warmColor
            text.firstMaterial?.lightingModel = .constant
            let textNode = SCNNode(geometry: text)
            textNode.scale = SCNVector3(0.001, 0.001, 0.001)

            let plane = SCNPlane(width: 0.01, height: 0.005)
            plane.cornerRadius = 0.0025
            plane.firstMaterial?.diffuse.contents = warmColor
            plane.firstMaterial?.lightingModel = .constant
            let planeNode = SCNNode(geometry: plane)

            let warmupContainer = SCNNode()
            warmupContainer.position = SCNVector3(0, -100, 0)
            warmupContainer.opacity = 0.01
            warmupContainer.addChildNode(torusNode)
            warmupContainer.addChildNode(sphereNode)
            warmupContainer.addChildNode(cylNode)
            warmupContainer.addChildNode(textNode)
            warmupContainer.addChildNode(planeNode)

            sceneView.scene.rootNode.addChildNode(warmupContainer)

            sceneView.prepare([torus, sphere, cyl, text, plane]) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    warmupContainer.removeFromParentNode()
                }
            }
        }

        // MARK: Per-frame update

        nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            DispatchQueue.main.async { [weak self] in
                self?.performFrameUpdate()
            }
        }

        private func performFrameUpdate() {
            guard let sceneView else { return }
            let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)

            guard let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any) else {
                controller.isSurfaceDetected = false
                crosshairNode?.isHidden = true
                return
            }
            let results = sceneView.session.raycast(query)
            guard let hit = results.first else {
                controller.isSurfaceDetected = false
                crosshairNode?.isHidden = true
                return
            }

            let col3 = hit.worldTransform.columns.3
            let position = SCNVector3(col3.x, col3.y, col3.z)

            controller.crosshairWorldPosition = position
            controller.isSurfaceDetected = true

            let col1 = hit.worldTransform.columns.1
            controller.surfaceNormal = SIMD3<Float>(col1.x, col1.y, col1.z)

            updateCrosshairNode(position: position, transform: hit.worldTransform)
            updateLiveLine()
            updateClosingPreview()
            updateLabelPositions()
        }

        private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
            SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
        }

        private func getVisibleMidpoint(start: SCNVector3, end: SCNVector3) -> SCNVector3 {
            guard let sceneView else {
                return SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2 + 0.015, (start.z + end.z) / 2)
            }

            let steps = 150
            var firstT: Float? = nil
            var lastT: Float? = nil

            for i in 0...steps {
                let t = Float(i) / Float(steps)
                let pt = SCNVector3(
                    start.x + (end.x - start.x) * t,
                    start.y + (end.y - start.y) * t,
                    start.z + (end.z - start.z) * t
                )
                let proj = sceneView.projectPoint(pt)
                if proj.z >= 0.0 && proj.z <= 1.0 {
                    let padding: Float = 50
                    if proj.x >= padding && proj.x <= Float(sceneView.bounds.width) - padding &&
                       proj.y >= padding && proj.y <= Float(sceneView.bounds.height) - padding {
                        if firstT == nil { firstT = t }
                        lastT = t
                    }
                }
            }

            let finalT = (firstT != nil && lastT != nil) ? (firstT! + lastT!) / 2.0 : 0.5
            return SCNVector3(
                start.x + (end.x - start.x) * finalT,
                start.y + (end.y - start.y) * finalT + 0.015,
                start.z + (end.z - start.z) * finalT
            )
        }

        private func updateLabelScale(node: SCNNode) {
            guard let sceneView, let pov = sceneView.pointOfView else { return }
            let distance = simd_distance(node.simdPosition, pov.simdPosition)
            let s = max(0.5, distance * 1.5)
            node.scale = SCNVector3(s, s, s)
        }

        private func updateLabelPositions() {
            for segment in controller.segments {
                if let nodes = segmentNodes[segment.id] {
                    let target = getVisibleMidpoint(start: segment.start.scnVector3, end: segment.end.scnVector3)
                    nodes.label.position = lerp(nodes.label.position, target, 0.15)
                    updateLabelScale(node: nodes.label)
                }
            }
            if let start = controller.placedPoints.last, let end = controller.crosshairWorldPosition {
                let target = getVisibleMidpoint(start: start.scnVector3, end: end)
                if let liveLabel = liveLabelNode {
                    liveLabel.position = lerp(liveLabel.position, target, 0.25)
                    updateLabelScale(node: liveLabel)
                }
            }
            for (_, group) in finalizedAreaNodeGroups {
                updateLabelScale(node: group.label)
            }
        }

        private func updateCrosshairNode(position: SCNVector3, transform: simd_float4x4) {
            if crosshairNode == nil {
                let ring = SCNTorus(ringRadius: 0.012, pipeRadius: 0.001)
                ring.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.85)
                ring.firstMaterial?.lightingModel = .constant
                let node = SCNNode(geometry: ring)
                sceneView?.scene.rootNode.addChildNode(node)
                crosshairNode = node
            }
            guard let node = crosshairNode else { return }
            node.isHidden = false
            node.simdWorldTransform = transform
            node.simdScale = SIMD3<Float>(repeating: 1)
        }

        private func updateLiveLine() {
            guard let startPoint = controller.placedPoints.last,
                  let endPos = controller.crosshairWorldPosition else {
                liveLineNode?.isHidden = true
                liveLabelNode?.isHidden = true
                liveStartDotNode?.isHidden = true
                return
            }

            // If snapping to first point, suppress the live line
            if controller.isNearFirstPoint {
                liveLineNode?.isHidden = true
                liveLabelNode?.isHidden = true
                liveStartDotNode?.isHidden = false
                liveStartDotNode?.position = startPoint.scnVector3
                return
            }

            let start = startPoint.scnVector3
            let end = endPos

            if liveStartDotNode == nil {
                liveStartDotNode = makeDotNode(color: .white)
                sceneView?.scene.rootNode.addChildNode(liveStartDotNode!)
            }
            liveStartDotNode?.isHidden = false
            liveStartDotNode?.position = start

            let dist = simd_distance(startPoint.position, SIMD3<Float>(end.x, end.y, end.z))
            if dist < 0.001 {
                liveLineNode?.isHidden = true
                liveLabelNode?.isHidden = true
                return
            }

            if liveLineNode == nil {
                liveLineNode = makeLineNode(from: start, to: end, distance: dist, color: .white)
                sceneView?.scene.rootNode.addChildNode(liveLineNode!)
            } else {
                updateLineNode(liveLineNode!, from: start, to: end, distance: dist)
            }
            liveLineNode?.isHidden = false

            let labelStr: String
            if dist >= 1 { labelStr = String(format: "%.2f m", dist) }
            else { labelStr = String(format: "%.1f cm", dist * 100) }

            let mid = SCNVector3((start.x + end.x) / 2, (start.y + end.y) / 2 + 0.015, (start.z + end.z) / 2)

            if liveLabelNode == nil {
                liveLabelNode = makeLabelNode(text: labelStr, at: mid)
                sceneView?.scene.rootNode.addChildNode(liveLabelNode!)
            } else {
                updateLabelNode(liveLabelNode!, text: labelStr, at: mid)
            }
            liveLabelNode?.isHidden = false
        }

        func syncNodes() {
            let currentIDs = Set(controller.segments.map(\.id))

            for id in segmentNodes.keys where !currentIDs.contains(id) {
                let nodes = segmentNodes.removeValue(forKey: id)
                nodes?.line.removeFromParentNode()
                nodes?.label.removeFromParentNode()
                nodes?.startDot.removeFromParentNode()
                nodes?.endDot.removeFromParentNode()
            }

            for segment in controller.segments where segmentNodes[segment.id] == nil {
                let start = segment.start.scnVector3
                let end = segment.end.scnVector3

                let lineNode = makeLineNode(from: start, to: end, distance: segment.distance, color: .white)
                sceneView?.scene.rootNode.addChildNode(lineNode)

                let labelNode = makeLabelNode(text: segment.formattedDistance, at: segment.midpoint)
                sceneView?.scene.rootNode.addChildNode(labelNode)

                let startDot = makeDotNode(color: .white)
                startDot.position = start
                sceneView?.scene.rootNode.addChildNode(startDot)

                let endDot = makeDotNode(color: .white)
                endDot.position = end
                sceneView?.scene.rootNode.addChildNode(endDot)

                segmentNodes[segment.id] = (lineNode, labelNode, startDot, endDot)
            }

            if !controller.isLiveMeasuring {
                liveLineNode?.removeFromParentNode()
                liveLineNode = nil
                liveLabelNode?.removeFromParentNode()
                liveLabelNode = nil
                liveStartDotNode?.removeFromParentNode()
                liveStartDotNode = nil
            }

            syncAreaNodes()
        }

        // MARK: Node factories

        private func makeDotNode(color: UIColor) -> SCNNode {
            let sphere = SCNSphere(radius: 0.004)
            sphere.firstMaterial?.diffuse.contents = color
            sphere.firstMaterial?.lightingModel = .constant
            return SCNNode(geometry: sphere)
        }

        private func makeLineNode(from start: SCNVector3, to end: SCNVector3, distance: Float, color: UIColor) -> SCNNode {
            let cylinder = SCNCylinder(radius: 0.001, height: CGFloat(distance))
            cylinder.firstMaterial?.diffuse.contents = color
            cylinder.firstMaterial?.lightingModel = .constant

            let cylinderNode = SCNNode(geometry: cylinder)
            cylinderNode.name = "_cyl"
            cylinderNode.position = SCNVector3(0, distance / 2, 0)

            let wrapper = SCNNode()
            wrapper.addChildNode(cylinderNode)
            wrapper.position = start
            wrapper.look(at: end, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            return wrapper
        }

        private func updateLineNode(_ node: SCNNode, from start: SCNVector3, to end: SCNVector3, distance: Float) {
            if let cylNode = node.childNode(withName: "_cyl", recursively: false),
               let cyl = cylNode.geometry as? SCNCylinder {
                cyl.height = CGFloat(distance)
                cylNode.position = SCNVector3(0, distance / 2, 0)
            }
            node.position = start
            node.look(at: end, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        }

        private func makeLabelNode(text: String, at position: SCNVector3) -> SCNNode {
            let scnText = SCNText(string: text, extrusionDepth: 0)
            scnText.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            scnText.flatness = 0.3
            scnText.firstMaterial?.diffuse.contents = UIColor.white
            scnText.firstMaterial?.lightingModel = .constant
            scnText.firstMaterial?.isDoubleSided = true

            let textNode = SCNNode(geometry: scnText)
            textNode.name = "_txt"
            let (min, max) = textNode.boundingBox
            let textW = max.x - min.x
            let textH = max.y - min.y
            textNode.pivot = SCNMatrix4MakeTranslation(textW / 2, textH / 2, 0)

            let scale: Float = 0.001
            textNode.scale = SCNVector3(scale, scale, scale)

            let padding: CGFloat = 6
            let bgW = CGFloat(textW) * CGFloat(scale) + 0.008
            let bgH = CGFloat(textH) * CGFloat(scale) + 0.004
            let bg = SCNPlane(width: bgW + padding * 0.001, height: bgH + padding * 0.001)
            bg.cornerRadius = bgH / 2
            bg.firstMaterial?.diffuse.contents = UIColor.black.withAlphaComponent(0.65)
            bg.firstMaterial?.lightingModel = .constant
            bg.firstMaterial?.isDoubleSided = true
            let bgNode = SCNNode(geometry: bg)
            bgNode.name = "_bg"
            bgNode.position = SCNVector3(0, 0, -0.0005)

            let container = SCNNode()
            container.addChildNode(bgNode)
            container.addChildNode(textNode)
            container.position = position
            container.constraints = [SCNBillboardConstraint()]
            return container
        }

        private func updateLabelNode(_ node: SCNNode, text: String, at position: SCNVector3) {
            guard let textNode = node.childNode(withName: "_txt", recursively: false),
                  let scnText = textNode.geometry as? SCNText else { return }

            let oldStr = scnText.string as? String ?? ""
            guard oldStr != text else {
                node.position = position
                return
            }

            scnText.string = text

            let (min, max) = textNode.boundingBox
            let textW = max.x - min.x
            let textH = max.y - min.y
            textNode.pivot = SCNMatrix4MakeTranslation(textW / 2, textH / 2, 0)

            if let bgNode = node.childNode(withName: "_bg", recursively: false),
               let bg = bgNode.geometry as? SCNPlane {
                let scale: CGFloat = 0.001
                let padding: CGFloat = 6
                bg.width  = CGFloat(textW) * scale + 0.008 + padding * 0.001
                bg.height = CGFloat(textH) * scale + 0.004 + padding * 0.001
                bg.cornerRadius = bg.height / 2
            }

            node.position = position
        }

        // MARK: Area Visualization

        private func syncAreaNodes() {
            // Sync finalized area polygons (fill + label only; edges are already in segments)
            let currentFinalizedIDs = Set(controller.finalizedAreas.map(\.id))

            for id in finalizedAreaNodeGroups.keys where !currentFinalizedIDs.contains(id) {
                let group = finalizedAreaNodeGroups.removeValue(forKey: id)
                group?.fill.removeFromParentNode()
                group?.label.removeFromParentNode()
            }

            for polygon in controller.finalizedAreas where finalizedAreaNodeGroups[polygon.id] == nil {
                let fill = makePolygonFillNode(points: polygon.points, color: UIColor.systemBlue.withAlphaComponent(0.15))
                sceneView?.scene.rootNode.addChildNode(fill)

                let label = makeLabelNode(text: polygon.formattedArea, at: polygon.centroid)
                sceneView?.scene.rootNode.addChildNode(label)

                finalizedAreaNodeGroups[polygon.id] = (fill, label)
            }

            // Snap indicator: show a pulsing ring at the first point when near
            if controller.isNearFirstPoint, let first = controller.placedPoints.first {
                if snapIndicatorNode == nil {
                    let ring = SCNTorus(ringRadius: 0.02, pipeRadius: 0.003)
                    ring.firstMaterial?.diffuse.contents = UIColor.systemGreen
                    ring.firstMaterial?.lightingModel = .constant
                    let node = SCNNode(geometry: ring)
                    sceneView?.scene.rootNode.addChildNode(node)
                    snapIndicatorNode = node
                }
                snapIndicatorNode?.position = first.scnVector3
                snapIndicatorNode?.isHidden = false
            } else {
                snapIndicatorNode?.isHidden = true
            }
        }

        private func updateClosingPreview() {
            // Show a dashed-style preview line from crosshair back to first point when 2+ points placed
            guard controller.placedPoints.count >= 2,
                  let firstPoint = controller.placedPoints.first,
                  let crosshairPos = controller.crosshairWorldPosition else {
                closingPreviewLineNode?.isHidden = true
                return
            }

            let end = crosshairPos
            let closeDist = simd_distance(SIMD3<Float>(end.x, end.y, end.z), firstPoint.position)
            guard closeDist > 0.005 else {
                closingPreviewLineNode?.isHidden = true
                return
            }

            let color: UIColor = controller.isNearFirstPoint
                ? .systemGreen.withAlphaComponent(0.8)
                : .white.withAlphaComponent(0.25)

            if closingPreviewLineNode == nil {
                closingPreviewLineNode = makeLineNode(from: end, to: firstPoint.scnVector3, distance: closeDist, color: color)
                sceneView?.scene.rootNode.addChildNode(closingPreviewLineNode!)
            } else {
                updateLineNode(closingPreviewLineNode!, from: end, to: firstPoint.scnVector3, distance: closeDist)
                if let cyl = closingPreviewLineNode?.childNode(withName: "_cyl", recursively: false)?.geometry as? SCNCylinder {
                    cyl.firstMaterial?.diffuse.contents = color
                }
            }
            closingPreviewLineNode?.isHidden = false
        }

        private func makePolygonFillNode(points: [MeasurementPoint], color: UIColor) -> SCNNode {
            guard points.count >= 3 else { return SCNNode() }

            let vertices = points.map { $0.scnVector3 }
            var indices: [UInt16] = []
            for i in 1..<(vertices.count - 1) {
                indices.append(0)
                indices.append(UInt16(i))
                indices.append(UInt16(i + 1))
            }

            let vertexSource = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
            geometry.firstMaterial?.diffuse.contents = color
            geometry.firstMaterial?.lightingModel = .constant
            geometry.firstMaterial?.isDoubleSided = true

            return SCNNode(geometry: geometry)
        }
    }
}
#endif
