import Foundation

public struct Diagram: Codable, Equatable {
    public struct Node: Codable, Equatable, Identifiable {
        public let id: String
        public let label: String
        public let detail: String
        public let shape: String
        public let color: String
        public let x: Double
        public let y: Double
        public let z: Double
        public let size: Double
        public init(id: String, label: String, detail: String, shape: String = "box", color: String = "C9F76E", x: Double, y: Double, z: Double = 0, size: Double = 0.7) {
            self.id = id; self.label = label; self.detail = detail; self.shape = shape; self.color = color; self.x = x; self.y = y; self.z = z; self.size = size
        }
    }
    public struct Link: Codable, Equatable {
        public let from: String
        public let to: String
        public let label: String
        public init(from: String, to: String, label: String) { self.from = from; self.to = to; self.label = label }
    }
    public let title: String
    public let explanation: String
    public let nodes: [Node]
    public let links: [Link]
    public init(title: String, explanation: String, nodes: [Node], links: [Link]) { self.title = title; self.explanation = explanation; self.nodes = nodes; self.links = links }
    public func validated() throws -> Self {
        let ids = Set(nodes.map(\.id))
        guard !title.isEmpty, title.count <= 120, explanation.count <= 6000, (1...24).contains(nodes.count), links.count <= 40, ids.count == nodes.count,
              nodes.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 40 && !$0.label.isEmpty && $0.label.count <= 80 && $0.detail.count <= 1000 && ["box", "sphere", "cylinder", "cone"].contains($0.shape) && $0.color.count == 6 && $0.color.allSatisfy(\.isHexDigit) && [$0.x, $0.y, $0.z, $0.size].allSatisfy(\.isFinite) && abs($0.x) <= 4 && abs($0.y) <= 3 && abs($0.z) <= 3 && (0.2...1.6).contains($0.size) }),
              links.allSatisfy({ ids.contains($0.from) && ids.contains($0.to) && $0.from != $0.to && $0.label.count <= 80 }) else { throw CommandError.invalid("The diagram contains unsupported shapes, links, or coordinates.") }
        return self
    }
    public static let example = Diagram(title: "How a web request travels", explanation: "A simplified view of a browser requesting a page. Select each component for its role; orbit the 3D view to explore the scene.", nodes: [
        Node(id: "browser", label: "Browser", detail: "The browser asks for a resource and renders the response.", color: "C9F76E", x: -3, y: 0),
        Node(id: "network", label: "Network", detail: "The network transports request and response data. DNS and TLS are omitted from this simplified view.", shape: "sphere", color: "79D5FF", x: 0, y: 1),
        Node(id: "server", label: "Server", detail: "The server processes the request and sends a response.", shape: "cylinder", color: "B8A2FF", x: 3, y: 0)
    ], links: [Link(from: "browser", to: "network", label: "Request"), Link(from: "network", to: "server", label: "HTTPS")])
}
