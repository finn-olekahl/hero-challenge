//
//  ARSceneView.swift
//  hero-challenge
//

import SwiftUI

#if os(iOS)
import ARKit
import SceneKit
import UIKit

// MARK: - UIViewRepresentable

struct ARSceneView: UIViewRepresentable {
    let viewModel: MeasureViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.delegate = context.coordinator
        view.session.delegate = context.coordinator
        view.scene = SCNScene()
        view.automaticallyUpdatesLighting = false
        view.autoenablesDefaultLighting = false
        view.rendersContinuously = true

        context.coordinator.sceneView = view
        context.coordinator.startSession()
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.syncNodes()
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        private let viewModel: MeasureViewModel
        weak var sceneView: ARSCNView?

        // Persistent SceneKit nodes
        private var crosshairNode: SCNNode?
        private var liveLineNode: SCNNode?
        private var liveLabelNode: SCNNode?
        private var liveStartDotNode: SCNNode?

        // Finalised segment nodes keyed by segment id
        private var segmentNodes: [UUID: (line: SCNNode, label: SCNNode, startDot: SCNNode, endDot: SCNNode)] = [:]

        init(viewModel: MeasureViewModel) {
            self.viewModel = viewModel
            super.init()
        }

        // MARK: Session

        func startSession() {
            guard ARWorldTrackingConfiguration.isSupported, let sceneView else {
                viewModel.instructionText = "AR is not available on this device."
                return
            }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            sceneView.session.run(config, options: [.resetTracking, .removeExistingAnchors])

            prewarmShaders()
        }

        /// Add tiny invisible nodes that use every geometry type we need, so SceneKit
        /// compiles the Metal shaders during the first few render passes instead of
        /// when the user taps for the first time.
        private func prewarmShaders() {
            guard let sceneView else { return }

            // Use a nearly-invisible (but non-zero alpha) colour so the GPU
            // actually executes the fragment shader and compiles it.
            let warmColor = UIColor.white.withAlphaComponent(0.02)

            // -- Torus (crosshair ring) --
            let torus = SCNTorus(ringRadius: 0.012, pipeRadius: 0.001)
            torus.firstMaterial?.diffuse.contents = warmColor
            torus.firstMaterial?.lightingModel = .constant
            let torusNode = SCNNode(geometry: torus)

            // -- Sphere (dot) --
            let sphere = SCNSphere(radius: 0.004)
            sphere.firstMaterial?.diffuse.contents = warmColor
            sphere.firstMaterial?.lightingModel = .constant
            let sphereNode = SCNNode(geometry: sphere)

            // -- Cylinder (line) --
            let cyl = SCNCylinder(radius: 0.001, height: 0.01)
            cyl.firstMaterial?.diffuse.contents = warmColor
            cyl.firstMaterial?.lightingModel = .constant
            let cylNode = SCNNode(geometry: cyl)

            // -- SCNText (label) — use a realistic string to force full font load --
            let text = SCNText(string: "12.5 cm", extrusionDepth: 0)
            text.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            text.flatness = 0.3
            text.firstMaterial?.diffuse.contents = warmColor
            text.firstMaterial?.lightingModel = .constant
            let textNode = SCNNode(geometry: text)
            textNode.scale = SCNVector3(0.001, 0.001, 0.001)

            // -- SCNPlane (label background) --
            let plane = SCNPlane(width: 0.01, height: 0.005)
            plane.cornerRadius = 0.0025
            plane.firstMaterial?.diffuse.contents = warmColor
            plane.firstMaterial?.lightingModel = .constant
            let planeNode = SCNNode(geometry: plane)

            // Group them under one invisible container placed far away
            let warmupContainer = SCNNode()
            warmupContainer.position = SCNVector3(0, -100, 0)        // out of view
            warmupContainer.opacity = 0.01                            // nearly invisible but still rendered
            warmupContainer.addChildNode(torusNode)
            warmupContainer.addChildNode(sphereNode)
            warmupContainer.addChildNode(cylNode)
            warmupContainer.addChildNode(textNode)
            warmupContainer.addChildNode(planeNode)

            // Add to scene so SceneKit actually renders them and compiles shaders
            sceneView.scene.rootNode.addChildNode(warmupContainer)

            // Eagerly compile shaders on a background thread, then remove
            sceneView.prepare([torus, sphere, cyl, text, plane]) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    warmupContainer.removeFromParentNode()
                }
            }
        }

        // MARK: Per-frame update

        nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // SceneKit calls this on its render thread — bounce to main.
            DispatchQueue.main.async { [weak self] in
                self?.performFrameUpdate()
            }
        }

        private func performFrameUpdate() {
            guard let sceneView else { return }
            let center = CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY)

            guard let query = sceneView.raycastQuery(from: center, allowing: .estimatedPlane, alignment: .any) else {
                viewModel.isSurfaceDetected = false
                crosshairNode?.isHidden = true
                return
            }
            let results = sceneView.session.raycast(query)
            guard let hit = results.first else {
                viewModel.isSurfaceDetected = false
                crosshairNode?.isHidden = true
                return
            }

            let col3 = hit.worldTransform.columns.3
            let position = SCNVector3(col3.x, col3.y, col3.z)

            viewModel.crosshairWorldPosition = position
            viewModel.isSurfaceDetected = true

            // Surface normal from the hit transform (the Y column = surface normal)
            let col1 = hit.worldTransform.columns.1
            viewModel.surfaceNormal = SIMD3<Float>(col1.x, col1.y, col1.z)

            // Update crosshair indicator
            updateCrosshairNode(position: position, transform: hit.worldTransform)

            // Update live measurement line
            updateLiveLine()

            // Update label positions to stick to the visible center
            updateLabelPositions()
        }

        private func lerp(_ a: SCNVector3, _ b: SCNVector3, _ t: Float) -> SCNVector3 {
            return SCNVector3(
                a.x + (b.x - a.x) * t,
                a.y + (b.y - a.y) * t,
                a.z + (b.z - a.z) * t
            )
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
                // z <= 1 indicates it's in front of camera
                if proj.z >= 0.0 && proj.z <= 1.0 {
                    let padding: Float = 50 // keep it from edge
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
            guard let sceneView = sceneView, let pov = sceneView.pointOfView else { return }
            // Scale dynamically based on distance to camera so it remains legible
            let distance = simd_distance(node.simdPosition, pov.simdPosition)
            let s = max(0.5, distance * 1.5) // Adjust multiplier as needed
            node.scale = SCNVector3(s, s, s)
        }

        private func updateLabelPositions() {
            // Update finalized segments
            for segment in viewModel.segments {
                if let nodes = segmentNodes[segment.id] {
                    let target = getVisibleMidpoint(start: segment.start.scnVector3, end: segment.end.scnVector3)
                    // Smoothly interpolate towards the target position
                    nodes.label.position = lerp(nodes.label.position, target, 0.15)
                    updateLabelScale(node: nodes.label)
                }
            }
            // Update live line
            if let start = viewModel.currentStartPoint, let end = viewModel.crosshairWorldPosition {
                let target = getVisibleMidpoint(start: start.scnVector3, end: end)
                if let liveLabel = liveLabelNode {
                    liveLabel.position = lerp(liveLabel.position, target, 0.25)
                    updateLabelScale(node: liveLabel)
                }
            }
        }

        // MARK: Crosshair indicator (3-D ring on surfaces)

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
            // Zero-out scale from transform — keep only rotation + position
            node.simdScale = SIMD3<Float>(repeating: 1)
        }

        // MARK: Live line + label while measuring

        private func updateLiveLine() {
            guard let startPoint = viewModel.currentStartPoint,
                  let endPos = viewModel.crosshairWorldPosition else {
                liveLineNode?.isHidden = true
                liveLabelNode?.isHidden = true
                liveStartDotNode?.isHidden = true
                return
            }

            let start = startPoint.scnVector3
            let end = endPos

            // --- Start dot ---
            if liveStartDotNode == nil {
                liveStartDotNode = makeDotNode(color: .white)
                sceneView?.scene.rootNode.addChildNode(liveStartDotNode!)
            }
            liveStartDotNode?.isHidden = false
            liveStartDotNode?.position = start

            // --- Line (reuse node, update geometry in place) ---
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

            // --- Label (reuse node, update text string in place) ---
            let labelStr: String
            if dist >= 1 { labelStr = String(format: "%.2f m", dist) }
            else { labelStr = String(format: "%.1f cm", dist * 100) }

            let mid = SCNVector3(
                (start.x + end.x) / 2,
                (start.y + end.y) / 2 + 0.015,
                (start.z + end.z) / 2
            )

            if liveLabelNode == nil {
                liveLabelNode = makeLabelNode(text: labelStr, at: mid)
                sceneView?.scene.rootNode.addChildNode(liveLabelNode!)
            } else {
                updateLabelNode(liveLabelNode!, text: labelStr, at: mid)
            }
            liveLabelNode?.isHidden = false
        }

        // MARK: Sync finalised segments

        func syncNodes() {
            let currentIDs = Set(viewModel.segments.map(\.id))

            // Remove nodes for deleted segments
            for id in segmentNodes.keys where !currentIDs.contains(id) {
                let nodes = segmentNodes.removeValue(forKey: id)
                nodes?.line.removeFromParentNode()
                nodes?.label.removeFromParentNode()
                nodes?.startDot.removeFromParentNode()
                nodes?.endDot.removeFromParentNode()
            }

            // Add nodes for new segments
            for segment in viewModel.segments where segmentNodes[segment.id] == nil {
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

            // If we cleared everything, also remove live nodes
            if !viewModel.isLiveMeasuring {
                liveLineNode?.removeFromParentNode()
                liveLineNode = nil
                liveLabelNode?.removeFromParentNode()
                liveLabelNode = nil
                liveStartDotNode?.removeFromParentNode()
                liveStartDotNode = nil
            }
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
            // Background panel with text — flat extrusion (0) for speed
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

            // Dark background plane
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

            // Resize background
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
    }
}
#endif
