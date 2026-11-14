import Foundation
import CoreGraphics

public struct NotchGridGeometry {
    public static let spacing = 12.0
    public let columns: Int
    public let rows: Int
    public let cardWidth: CGFloat
    public let minimumHeight: CGFloat

    public static func calculate(width: CGFloat, sectionCount: Int, rowHeight: CGFloat) -> Self {
        let width = width.isFinite ? min(100000, max(1, width)) : 1
        let count = min(NotchSection.allCases.count, max(0, sectionCount))
        let columns = min(max(1, count), max(1, Int((width + spacing) / (240 + spacing))))
        let rows = count == 0 ? 0 : (count + columns - 1) / columns
        let cardWidth = max(1, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let safeRowHeight = rowHeight.isFinite ? max(1, rowHeight) : 1
        let minimumHeight = CGFloat(rows) * safeRowHeight + CGFloat(max(0, rows - 1)) * spacing
        return Self(columns: columns, rows: rows, cardWidth: cardWidth, minimumHeight: minimumHeight)
    }
}
