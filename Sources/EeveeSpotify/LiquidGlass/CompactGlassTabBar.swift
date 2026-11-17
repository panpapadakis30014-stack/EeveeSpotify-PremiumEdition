import UIKit

// Spotify's offline strip leaves a 49-point tab area. UITabBar's floating iOS
// layout does not fit there, so use the same items/actions in a compact glass row.
@available(iOS 26.0, *)
final class CompactGlassTabBar: UIView {
    var onSelect: ((Int) -> Void)?
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private var buttons: [CompactGlassTabButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        glass.isUserInteractionEnabled = false
        glass.cornerConfiguration = .capsule()
        addSubview(glass)
        accessibilityIdentifier = "eeveeCompactGlassTabs"
    }

    required init?(coder: NSCoder) { nil }

    func update(items: [UITabBarItem], selected: UITabBarItem?, tint: UIColor) {
        if buttons.count != items.count {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = items.enumerated().map { index, _ in
                let button = CompactGlassTabButton()
                button.tag = index
                button.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
                addSubview(button)
                return button
            }
        }
        for (button, item) in zip(buttons, items) {
            button.update(item: item, selected: item === selected, tint: tint)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds.insetBy(dx: 8, dy: 2)
        let frames = GlassTabBarGeometry.compactItemFrames(in: bounds, count: buttons.count)
        for (button, frame) in zip(buttons, frames) { button.frame = frame }
    }

    @objc private func tapped(_ sender: UIButton) { onSelect?(sender.tag) }
}

@available(iOS 26.0, *)
private final class CompactGlassTabButton: UIButton {
    private let glyph = UIImageView()
    private let caption = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        caption.font = .systemFont(ofSize: 10, weight: .medium)
        caption.textAlignment = .center
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.8
        caption.isUserInteractionEnabled = false
        addSubview(glyph)
        addSubview(caption)
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) { nil }

    func update(item: UITabBarItem, selected: Bool, tint: UIColor) {
        glyph.image = selected ? (item.selectedImage ?? item.image) : item.image
        glyph.tintColor = selected ? tint : UIColor(white: 1, alpha: 0.7)
        caption.text = item.title
        caption.textColor = glyph.tintColor
        backgroundColor = selected ? UIColor(white: 1, alpha: 0.12) : .clear
        accessibilityLabel = item.title ?? item.accessibilityLabel
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let hasCaption = !(caption.text ?? "").isEmpty
        let imageSide = min(22, bounds.height - 8)
        let textHeight: CGFloat = hasCaption ? 12 : 0
        let total = imageSide + (hasCaption ? 2 : 0) + textHeight
        let y = (bounds.height - total) / 2
        glyph.frame = CGRect(x: (bounds.width - imageSide) / 2, y: y, width: imageSide, height: imageSide)
        caption.frame = CGRect(x: 2, y: glyph.frame.maxY + 2, width: max(0, bounds.width - 4), height: textHeight)
    }
}
