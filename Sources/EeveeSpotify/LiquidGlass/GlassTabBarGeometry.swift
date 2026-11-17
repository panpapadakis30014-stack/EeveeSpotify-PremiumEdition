import Foundation

enum GlassTabBarGeometry {
    static func bottomInset(stockBottom: CGFloat, windowBottom: CGFloat, homeInset: CGFloat) -> CGFloat {
        max(0, homeInset - max(0, windowBottom - stockBottom))
    }

    static func phoneFrame(in bounds: CGRect, bottomInset: CGFloat) -> CGRect {
        let height: CGFloat = 49 + bottomInset
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }
}
