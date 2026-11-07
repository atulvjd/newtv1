import SwiftUI
import SceneKit
import AppKit
import Newtv1Core
import UniformTypeIdentifiers

private typealias DiagramState<T> = SwiftUI.State<T>
struct DiagramStudio: View {
    @ObservedObject var model: AppModel
    @DiagramState private var prompt = ""
    @DiagramState private var threeD = true
    @DiagramState private var selected: String?
    @DiagramState private var reset = UUID()
    private var diagram: Diagram { model.diagram }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make an idea visible.").font(.system(size: 29, weight: .semibold))
            Text("Explain a topic as connected shapes. Use 2D to inspect the relationships or orbit a 3D scene. Generated explanations can be inaccurate; check them before relying on them.").font(.system(size: 12)).foregroundStyle(.gray)
            HStack {
                TextField("For example: explain the water cycle", text: $prompt).textFieldStyle(.roundedBorder)
                Button("Create diagram") { model.generateDiagram(prompt) }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                if model.busy { Button("Stop") { model.stop() } }
            }
            HStack {
                Picker("View", selection: $threeD) { Text("2D diagram").tag(false); Text("3D scene").tag(true) }.pickerStyle(.segmented).frame(width: 240)
                Spacer()
                Button("Reset view") { reset = UUID(); selected = nil }
                Button("Example") { model.diagram = .example; reset = UUID() }
                Button("Import…", action: importDiagram)
                Button("Export…", action: exportDiagram)
            }.buttonStyle(.bordered)
            Text(diagram.title).font(.system(size: 22, weight: .medium))
            if threeD {
                SceneView(scene: scene(), options: [.allowsCameraControl, .autoenablesDefaultLighting]).id(reset.uuidString + diagram.title + String(diagram.nodes.count)).frame(height: 380).clipShape(RoundedRectangle(cornerRadius: 14))
                Text("Drag to orbit · scroll to zoom · use the component buttons below for details.").font(.system(size: 10)).foregroundStyle(.gray)
            } else {
                GeometryReader { proxy in
                    ZStack {
                        ForEach(Array(diagram.links.enumerated()), id: \.offset) { _, link in
                            if let from = diagram.nodes.first(where: { $0.id == link.from }), let to = diagram.nodes.first(where: { $0.id == link.to }) {
                                Path { path in path.move(to: point(from, proxy.size)); path.addLine(to: point(to, proxy.size)) }.stroke(.white.opacity(0.28), lineWidth: 2)
                                Text(link.label).font(.system(size: 10)).foregroundStyle(.gray).padding(4).background(.black.opacity(0.8)).position(x: (point(from, proxy.size).x + point(to, proxy.size).x) / 2, y: (point(from, proxy.size).y + point(to, proxy.size).y) / 2 - 16)
                            }
                        }
                        ForEach(diagram.nodes) { node in
                            Button { selected = node.id } label: { Text(node.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black).lineLimit(2).frame(width: 105, height: 54).background(color(node.color), in: RoundedRectangle(cornerRadius: node.shape == "sphere" ? 27 : 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(selected == node.id ? 1 : 0), lineWidth: 3)) }.buttonStyle(.plain).position(point(node, proxy.size))
                        }
                    }
                }.frame(height: 380).background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            }
            Text(diagram.explanation).font(.system(size: 13)).foregroundStyle(.gray).lineSpacing(4).textSelection(.enabled)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) { ForEach(diagram.nodes) { node in Button(node.label) { selected = node.id }.buttonStyle(.bordered).tint(color(node.color)) } }
            if let node = diagram.nodes.first(where: { $0.id == selected }) { VStack(alignment: .leading, spacing: 8) { Text(node.label).font(.system(size: 17, weight: .medium)); Text(node.detail).font(.system(size: 12)).foregroundStyle(.gray).textSelection(.enabled) }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12)) }
        }
    }
    private func point(_ node: Diagram.Node, _ size: CGSize) -> CGPoint { CGPoint(x: 65 + (node.x + 4) / 8 * max(1, size.width - 130), y: 45 + (3 - node.y) / 6 * max(1, size.height - 90)) }
    private func color(_ hex: String) -> Color { let value = UInt64(hex, radix: 16) ?? 0xC9F76E; return Color(red: Double(value >> 16 & 255)/255, green: Double(value >> 8 & 255)/255, blue: Double(value & 255)/255) }
    private func scene() -> SCNScene {
        let scene = SCNScene(); scene.background.contents = NSColor(calibratedWhite: 0.025, alpha: 1)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 4.2; camera.position = SCNVector3(0, 0, 12); scene.rootNode.addChildNode(camera)
        for item in diagram.nodes {
            let geometry: SCNGeometry
            switch item.shape {
            case "sphere": geometry = SCNSphere(radius: item.size / 2)
            case "cylinder": geometry = SCNCylinder(radius: item.size / 2, height: item.size)
            case "cone": geometry = SCNCone(topRadius: 0, bottomRadius: item.size / 2, height: item.size)
            default: geometry = SCNBox(width: item.size, height: item.size, length: item.size, chamferRadius: 0.06)
            }
            geometry.firstMaterial?.diffuse.contents = NSColor(color(item.color))
            let node = SCNNode(geometry: geometry); node.position = SCNVector3(item.x, item.y, item.z); node.name = item.id; scene.rootNode.addChildNode(node)
            let text = SCNText(string: item.label, extrusionDepth: 0.005); text.font = .systemFont(ofSize: 0.32); text.flatness = 0.2; text.firstMaterial?.diffuse.contents = NSColor.white
            let label = SCNNode(geometry: text); let bounds = label.boundingBox; label.pivot = SCNMatrix4MakeTranslation((bounds.max.x + bounds.min.x) / 2, 0, 0); label.position = SCNVector3(item.x, item.y + item.size / 2 + 0.2, item.z)
            label.constraints = [SCNBillboardConstraint()]; scene.rootNode.addChildNode(label)
        }
        for link in diagram.links {
            guard let a = diagram.nodes.first(where: { $0.id == link.from }), let b = diagram.nodes.first(where: { $0.id == link.to }) else { continue }
            let length = sqrt(pow(b.x-a.x,2) + pow(b.y-a.y,2) + pow(b.z-a.z,2))
            guard length > 0 else { continue }
            let line = SCNCylinder(radius: 0.018, height: length); line.firstMaterial?.diffuse.contents = NSColor.gray
            let node = SCNNode(geometry: line); node.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
            node.look(at: SCNVector3(b.x,b.y,b.z), up: SCNVector3(0,0,1), localFront: SCNVector3(0,1,0)); scene.rootNode.addChildNode(node)
        }
        return scene
    }
    private func importDiagram() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 200000 else { throw Newtv1Failure("Diagram is too large.") }; model.diagram = try JSONDecoder().decode(Diagram.self, from: Data(contentsOf: url)).validated(); selected = nil; reset = UUID() }
        catch { model.error = error.localizedDescription }
    }
    private func exportDiagram() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Newtv1-diagram.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(diagram).write(to: url, options: .atomic) }
        catch { model.error = error.localizedDescription }
    }
}
