import CoreGraphics

public enum WindowPlacement {
    /// Cocoa screen coordinates, including displays with negative origins and menu/Dock insets.
    public static func frame(_ position: String, visible: CGRect, currentSize: CGSize) -> CGRect? {
        guard visible.width.isFinite, visible.height.isFinite, visible.minX.isFinite, visible.minY.isFinite,
              visible.width > 0, visible.height > 0 else { return nil }
        var rect = visible
        switch position {
        case "left": rect.size.width /= 2
        case "right": rect.size.width /= 2; rect.origin.x += rect.width
        case "top": rect.size.height /= 2; rect.origin.y += rect.height
        case "bottom": rect.size.height /= 2
        case "topLeft", "topRight", "bottomLeft", "bottomRight":
            rect.size.width /= 2; rect.size.height /= 2
            if position.hasSuffix("Right") { rect.origin.x += rect.width }
            if position.hasPrefix("top") { rect.origin.y += rect.height }
        case "center":
            guard currentSize.width.isFinite, currentSize.height.isFinite, currentSize.width > 0, currentSize.height > 0 else { return nil }
            rect.size = CGSize(width: min(currentSize.width, visible.width), height: min(currentSize.height, visible.height))
            rect.origin = CGPoint(x: visible.midX - rect.width / 2, y: visible.midY - rect.height / 2)
        case "maximize": break
        default: return nil
        }
        return rect
    }
}
