import CoreGraphics
import Foundation

public enum NotchMotion {
    /// Monotonic easing keeps the panel inside its camera-safe start/end bounds.
    public static func progress(_ raw: Double, opening: Bool) -> Double {
        let t = raw.isFinite ? min(max(raw, 0), 1) : 1
        return opening ? 1 - pow(1 - t, 4) : t * t * (3 - 2 * t)
    }

    public static func frame(from start: CGRect, to end: CGRect, progress raw: Double, opening: Bool) -> CGRect {
        let p = progress(raw, opening: opening)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * p }
        return CGRect(x: mix(start.minX, end.minX), y: mix(start.minY, end.minY), width: mix(start.width, end.width), height: mix(start.height, end.height))
    }
}
