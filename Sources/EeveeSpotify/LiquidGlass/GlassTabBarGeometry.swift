import Foundation
import CoreGraphics

enum GlassTabBarGeometry {
    static func needsCompactRenderer(height: CGFloat, homeInset: CGFloat) -> Bool {
        height > 0 && height < 49 + homeInset - 0.5
    }

    static func compactItemFrames(in bounds: CGRect, count: Int) -> [CGRect] {
        guard count > 0 else { return [] }
        let available = bounds.insetBy(dx: 10, dy: 2)
        let width = max(0, available.width) / CGFloat(count)
        return (0..<count).map {
            CGRect(x: available.minX + CGFloat($0) * width, y: available.minY,
                   width: width, height: max(0, available.height))
        }
    }

    static func bottomInset(stockBottom: CGFloat, windowBottom: CGFloat, homeInset: CGFloat) -> CGFloat {
        max(0, homeInset - max(0, windowBottom - stockBottom))
    }

    static func phoneFrame(in bounds: CGRect, bottomInset: CGFloat) -> CGRect {
        let height: CGFloat = 49 + bottomInset
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }
}
