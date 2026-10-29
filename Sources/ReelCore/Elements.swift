import ApplicationServices
import CoreGraphics
import Foundation

/// An element of an app's accessibility tree, as much as finding a tape's target needs. The real one is `AXNode`;
/// tests use a fake.
public protocol ElementNode {
    var identifier: String? { get }
    /// What a tape's `"label"` can match: the title, the description and a string value.
    var labels: [String] { get }
    /// Global points, top left origin; nil when the element has no position.
    var frame: CGRect? { get }
    var children: [Self] { get }
}

public enum ElementSearch {
    /// Elements visited before giving up on a tree; a large table can hold far more than a demo needs.
    static let limit = 20000

    /// The first element breadth first that `target` names and that shows inside `bounds`. Breadth first prefers
    /// the shallower of two matches: a button over a label of the same name deep in a list.
    public static func find<Node: ElementNode>(_ target: Target, in roots: [Node], within bounds: CGRect) -> Node? {
        var queue = roots[...]
        var visited = 0
        while let node = queue.popFirst(), visited < limit {
            visited += 1
            if matches(node, target), let frame = node.frame, !frame.isEmpty, frame.intersects(bounds) {
                return node
            }
            queue.append(contentsOf: node.children)
        }
        return nil
    }

    static func matches(_ node: some ElementNode, _ target: Target) -> Bool {
        switch target {
        case let .label(text): node.labels.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == text }
        case let .identifier(id): node.identifier == id
        case .point, .css: false
        }
    }
}

/// An element of a running app, read through the Accessibility API.
public struct AXNode: ElementNode {
    public let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }

    public var identifier: String? {
        string("AXIdentifier")
    }

    public var labels: [String] {
        ["AXTitle", "AXDescription", "AXValue"].compactMap { string($0) }.filter { !$0.isEmpty }
    }

    public var frame: CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let position = axValue("AXPosition"), AXValueGetValue(position, .cgPoint, &origin),
              let extent = axValue("AXSize"), AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    public var children: [AXNode] {
        (attribute("AXChildren") as? [AXUIElement] ?? []).map(AXNode.init)
    }

    public var windows: [AXNode] {
        (attribute("AXWindows") as? [AXUIElement] ?? []).map(AXNode.init)
    }

    @discardableResult
    public func set(_ name: String, _ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    @discardableResult
    public func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    func attribute(_ name: String) -> AnyObject? {
        var raw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success else { return nil }
        return raw
    }

    private func string(_ name: String) -> String? {
        attribute(name) as? String
    }

    private func axValue(_ name: String) -> AXValue? {
        guard let raw = attribute(name), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (raw as! AXValue)
    }
}
