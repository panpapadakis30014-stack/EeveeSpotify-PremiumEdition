import Orion
import UIKit

// Eevee Home: a reimagined top of the Home tab. A greeting, a "now playing" hero card
// tinted from the current artwork (progress, controls, quick actions), one-tap glass
// tiles for the places people actually go and a row of pinned playlists/albums.
// Spotify's own shelves carry on underneath.
//
// The header lives inside Home's collection view, above its content, so it scrolls with
// the page and leaves Spotify's feed untouched.

struct EeveeHomeGroup: HookGroup {}

private let funkisClass: AnyClass? = NSClassFromString("_TtC19Home_FunkisPageImpl20FunkisViewController")

class EeveeHomePageHook: ClassHook<UIViewController> {
    typealias Group = EeveeHomeGroup
    static let targetName = "_TtC16Home_EvoPageImpl33EvoLoadableResourceViewController"

    func viewDidLayoutSubviews() {
        orig.viewDidLayoutSubviews()
        EeveeHome.install(in: target)
    }
}

func activateEeveeHome() {
    let options = ExtrasOptions.launch
    guard options.eeveeHome, options.homeGreeting || options.homeHero || options.homeTiles || !options.pinned.isEmpty else { return }
    guard NSClassFromString(EeveeHomePageHook.targetName) != nil else {
        PremiumDiag.note("eevee home: page class missing")
        return
    }
    Connectivity.start()
    EeveeHomeGroup().activate()
    PremiumDiag.note("eevee home active")
}

enum EeveeHome {
    private static var stateKey: UInt8 = 0
    private static var logged = false

    private final class Install {
        let header = EeveeHomeHeader()
        weak var list: UICollectionView?
        var applied: CGFloat = 0
        var expected: CGFloat?
        var scrolledToTop = false
        var applying = false
        var insetWatch: NSKeyValueObservation?
    }

    static func install(in page: UIViewController) {
        guard let root = page.viewIfLoaded,
              let list = root.subviews.first(where: { $0 is UICollectionView }) as? UICollectionView,
              list.bounds.width > 0 else { return }

        let state: Install
        if let existing = objc_getAssociatedObject(page, &stateKey) as? Install {
            state = existing
        } else {
            // Only Home's main feed, not other pages that reuse the same controller.
            var parent = page.parent
            var isHome = false
            while let current = parent {
                if let funkisClass, current.isKind(of: funkisClass) { isHome = true; break }
                parent = current.parent
            }
            guard isHome else { return }
            state = Install()
            objc_setAssociatedObject(page, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }

        if state.list !== list {
            state.list = list
            // Spotify also resets the inset outside layout (pull to refresh, the pill bar); putting
            // ours back in the same pass keeps the feed from sliding under the header for a frame.
            state.insetWatch = list.observe(\.contentInset, options: [.new]) { [weak state] list, _ in
                guard let state else { return }
                apply(state, to: list)
            }
            state.header.onHeightChange = { [weak state, weak list] in
                guard let state, let list else { return }
                apply(state, to: list)
            }
        }
        apply(state, to: list)
    }

    private static func apply(_ state: Install, to list: UICollectionView) {
        guard !state.applying else { return }
        state.applying = true
        defer { state.applying = false }

        let header = state.header
        let height = header.preferredHeight(for: list.bounds.width)

        // Spotify sets its own top inset (for the pill bar); ours goes on top of whatever it chose.
        let current = list.contentInset.top
        let base = state.expected == current ? current - state.applied : current
        let wanted = base + height
        if current != wanted {
            let atTop = list.contentOffset.y <= -list.adjustedContentInset.top + 2
            list.contentInset.top = wanted
            if atTop || !state.scrolledToTop {
                list.contentOffset.y = -list.adjustedContentInset.top
                state.scrolledToTop = true
            }
        }
        state.applied = height
        state.expected = wanted

        if header.superview !== list {
            header.layer.zPosition = 5
            list.addSubview(header)
        }
        let frame = CGRect(x: 0, y: -height, width: list.bounds.width, height: height)
        if header.frame != frame { header.frame = frame }

        if !logged {
            logged = true
            PremiumDiag.note("eevee home header \(Int(frame.width))x\(Int(height)) in \(NSStringFromClass(type(of: list))), base inset \(base)")
        }
    }
}

// MARK: - Style

private enum Style {
    static let margin: CGFloat = 16
    static let green = UIColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1)
    static let primary = UIColor.white
    static let secondary = UIColor(white: 1, alpha: 0.66)
    static let tertiary = UIColor(white: 1, alpha: 0.45)
    static let hairline = UIColor(white: 1, alpha: 0.12)

    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // System text styles, scaled with Dynamic Type but capped so the header keeps its shape.
    static func font(_ style: UIFont.TextStyle, _ size: CGFloat, _ weight: UIFont.Weight,
                     rounded: Bool = false, monospacedDigits: Bool = false, max: CGFloat) -> UIFont {
        var font = monospacedDigits ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                                    : UIFont.systemFont(ofSize: size, weight: weight)
        if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font, maximumPointSize: max)
    }

    static func spring(_ delay: TimeInterval = 0, _ animations: @escaping () -> Void) {
        guard !reduceMotion else {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: animations)
            return
        }
        UIView.animate(withDuration: 0.55, delay: delay, usingSpringWithDamping: 0.78, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: animations)
    }

    static func symbol(_ name: String, _ size: CGFloat, _ weight: UIImage.SymbolWeight = .bold) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
    }

    static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    // Frames that survive a running transform (press and entrance animations scale views).
    static func place(_ view: UIView, _ frame: CGRect) {
        let bounds = CGRect(origin: view.bounds.origin, size: frame.size)
        if view.bounds != bounds { view.bounds = bounds }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if view.center != center { view.center = center }
    }
}

private enum Haptics {
    static var enabled = true
    private static let selection = UISelectionFeedbackGenerator()
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notify = UINotificationFeedbackGenerator()

    static func prepare() {
        guard enabled else { return }
        selection.prepare()
        light.prepare()
    }

    static func tap() { if enabled { selection.selectionChanged() } }
    static func soft() { if enabled { light.impactOccurred() } }
    static func firm() { if enabled { medium.impactOccurred() } }
    static func success() { if enabled { notify.notificationOccurred(.success) } }
}

// Artwork accent: the most colourful of the artwork's dominant colours, brightened so it
// reads on a dark glass card. Greyscale covers fall back to a soft white.
private enum Accent {
    static let cache = NSCache<NSURL, UIColor>()

    static func from(_ image: UIImage, key: URL?, done: @escaping (UIColor) -> Void) {
        if let key, let cached = cache.object(forKey: key as NSURL) { done(cached); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let colors = AlbumArtColorExtractor.dominantColors(from: image, count: 4)
            let picked = colors.max { score($0) < score($1) } ?? colors.first
            let accent = picked.map(normalise) ?? Style.green
            if let key { cache.setObject(accent, forKey: key as NSURL) }
            DispatchQueue.main.async { done(accent) }
        }
    }

    private static func score(_ color: UIColor) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s * min(1, b * 1.6)
    }

    private static func normalise(_ color: UIColor) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 { return UIColor(white: 0.92, alpha: 1) }
        return UIColor(hue: h, saturation: min(max(s * 1.1, 0.4), 0.85), brightness: min(max(b, 0.78), 0.96), alpha: 1)
    }
}

// MARK: - Header

final class EeveeHomeHeader: UIView {
    var onHeightChange: (() -> Void)?

    private let greeting = UILabel()
    private let sublineIcon = UIImageView()
    private let subline = UILabel()
    private let hero = HeroCard()
    private var tiles: [HomeTile] = []
    private let pinnedTitle = UILabel()
    private let pinnedScroll = UIScrollView()
    private var pinnedChips: [PinChip] = []
    private var options = UserDefaults.extrasOptions
    private var ticker: Timer?
    private var appeared = false
    private var offline = Connectivity.isOffline
    private var lastHeight: CGFloat?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        overrideUserInterfaceStyle = .dark
        Haptics.enabled = options.homeHaptics

        greeting.textColor = Style.primary
        greeting.adjustsFontSizeToFitWidth = true
        greeting.minimumScaleFactor = 0.7
        greeting.accessibilityTraits = .header
        subline.textColor = Style.secondary
        sublineIcon.contentMode = .center
        sublineIcon.tintColor = Style.green
        [greeting, sublineIcon, subline].forEach(addSubview)

        hero.onPin = { [weak self] in self?.togglePin() }
        addSubview(hero)

        tiles = HomeTile.Kind.allCases.map { kind in
            let tile = HomeTile(kind)
            addSubview(tile)
            return tile
        }

        pinnedTitle.text = "Pinned"
        pinnedTitle.textColor = Style.primary
        pinnedTitle.accessibilityTraits = .header
        addSubview(pinnedTitle)
        pinnedScroll.showsHorizontalScrollIndicator = false
        pinnedScroll.alwaysBounceHorizontal = true
        pinnedScroll.clipsToBounds = false
        addSubview(pinnedScroll)

        applyFonts()
        rebuildPins()
        hero.actionsEnabled = options.heroActions
        hero.tintsFromArtwork = options.homeArtworkTint

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(optionsChanged), name: .eeveeExtrasChanged, object: nil)
        center.addObserver(self, selector: #selector(connectivityChanged), name: .eeveeConnectivityChanged, object: nil)
        center.addObserver(self, selector: #selector(textSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(refresh), name: UIApplication.didBecomeActiveNotification, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        ticker?.invalidate()
        ticker = nil
        guard window != nil else { return }
        offline = Connectivity.isOffline
        refresh()
        hero.windowDidChange()
        Haptics.prepare()
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        tick.tolerance = 0.2
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
        if !appeared {
            appeared = true
            layoutIfNeeded()
            playEntrance()
        }
    }

    // Sections rise into place one after another the first time Home appears.
    private func playEntrance() {
        let sections: [[UIView]] = [[greeting, sublineIcon, subline], [hero], tiles, [pinnedTitle, pinnedScroll]]
        var delay: TimeInterval = 0
        for group in sections {
            for view in group where !view.isHidden {
                view.alpha = 0
                if !Style.reduceMotion { view.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.98, y: 0.98) }
                Style.spring(delay) {
                    view.alpha = 1
                    view.transform = .identity
                }
                if group.count > 3 { delay += 0.025 }
            }
            delay += Style.reduceMotion ? 0 : 0.06
        }
    }

    @objc private func optionsChanged() {
        let old = options
        options = UserDefaults.extrasOptions
        Haptics.enabled = options.homeHaptics
        hero.actionsEnabled = options.heroActions
        hero.tintsFromArtwork = options.homeArtworkTint
        if old.pinned != options.pinned { rebuildPins() }
        refresh()
        setNeedsLayout()
        heightMayHaveChanged()
    }

    @objc private func connectivityChanged() {
        guard offline != Connectivity.isOffline else { return }
        offline = Connectivity.isOffline
        refresh()
        setNeedsLayout()
        Style.spring { self.layoutIfNeeded() }
    }

    @objc private func textSizeChanged() {
        applyFonts()
        tiles.forEach { $0.applyFonts() }
        pinnedChips.forEach { $0.applyFonts() }
        hero.applyFonts()
        setNeedsLayout()
        heightMayHaveChanged()
    }

    private func heightMayHaveChanged() {
        let before = lastHeight
        let height = preferredHeight(for: bounds.width)
        guard height != before else { return }
        onHeightChange?()
    }

    private func applyFonts() {
        greeting.font = Style.font(.largeTitle, 32, .heavy, rounded: true, max: 44)
        subline.font = Style.font(.subheadline, 14, .semibold, max: 19)
        pinnedTitle.font = Style.font(.title3, 19, .bold, rounded: true, max: 25)
        sublineIcon.image = Style.symbol("wifi.slash", subline.font.pointSize * 0.85)
    }

    private var showsPins: Bool { !options.pinned.isEmpty }
    private var greetingHeight: CGFloat { ceil(greeting.font.lineHeight) + 2 + ceil(subline.font.lineHeight) }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        let content = max(0, width - Style.margin * 2)
        var height: CGFloat = 4
        if options.homeGreeting { height += greetingHeight + 18 }
        if options.homeHero { height += HeroCard.preferredHeight(for: content) + 16 }
        if options.homeTiles { height += HomeTile.preferredHeight * 2 + 10 + 20 }
        if showsPins { height += ceil(pinnedTitle.font.lineHeight) + 10 + PinChip.height + 16 }
        let rounded = ceil(height + 6)
        lastHeight = rounded
        return rounded
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = Style.margin
        let w = bounds.width - m * 2
        var y: CGFloat = 4

        [greeting, sublineIcon, subline].forEach { $0.isHidden = !options.homeGreeting }
        if options.homeGreeting {
            let titleHeight = ceil(greeting.font.lineHeight)
            Style.place(greeting, CGRect(x: m, y: y, width: w, height: titleHeight))
            let lineY = y + titleHeight + 2
            let lineHeight = ceil(subline.font.lineHeight)
            sublineIcon.isHidden = !offline
            let iconWidth: CGFloat = offline ? lineHeight + 2 : 0
            Style.place(sublineIcon, CGRect(x: m, y: lineY, width: lineHeight, height: lineHeight))
            Style.place(subline, CGRect(x: m + iconWidth, y: lineY, width: w - iconWidth, height: lineHeight))
            y += greetingHeight + 18
        }

        hero.isHidden = !options.homeHero
        if options.homeHero {
            let height = HeroCard.preferredHeight(for: w)
            Style.place(hero, CGRect(x: m, y: y, width: w, height: height))
            y += height + 16
        }

        tiles.forEach { $0.isHidden = !options.homeTiles }
        if options.homeTiles {
            let columns: CGFloat = 3
            let spacing: CGFloat = 10
            let tileWidth = floor((w - spacing * (columns - 1)) / columns)
            let height = HomeTile.preferredHeight
            // Offline, Downloads moves to the front: it's the one place that still plays.
            let ordered = offline
                ? tiles.sorted { ($0.kind == .downloads ? 0 : 1, $0.kind.order) < ($1.kind == .downloads ? 0 : 1, $1.kind.order) }
                : tiles
            for (index, tile) in ordered.enumerated() {
                let row = CGFloat(index / 3), column = CGFloat(index % 3)
                Style.place(tile, CGRect(x: m + column * (tileWidth + spacing), y: y + row * (height + spacing),
                                         width: tileWidth, height: height))
            }
            y += height * 2 + spacing + 20
        }

        pinnedTitle.isHidden = !showsPins
        pinnedScroll.isHidden = !showsPins
        if showsPins {
            let titleHeight = ceil(pinnedTitle.font.lineHeight)
            Style.place(pinnedTitle, CGRect(x: m, y: y, width: w, height: titleHeight))
            Style.place(pinnedScroll, CGRect(x: 0, y: y + titleHeight + 10, width: bounds.width, height: PinChip.height))
            var x = m
            for chip in pinnedChips {
                let size = chip.sizeThatFits(CGSize(width: 240, height: PinChip.height))
                Style.place(chip, CGRect(x: x, y: 0, width: size.width, height: PinChip.height))
                x += size.width + 8
            }
            pinnedScroll.contentSize = CGSize(width: x + m - 8, height: PinChip.height)
        }
    }

    // MARK: Content

    @objc private func refresh() {
        guard window != nil || superview == nil else { return }
        if options.homeGreeting {
            let hour = Calendar.current.component(.hour, from: Date())
            let text: String
            switch hour {
            case 5..<12: text = "Good morning"
            case 12..<17: text = "Good afternoon"
            case 17..<22: text = "Good evening"
            default: text = "Good night"
            }
            if greeting.text != text { greeting.text = text }
            let line = offline ? "Offline · your downloads are ready" : Self.dateFormatter.string(from: Date())
            if subline.text != line { subline.text = line }
            if sublineIcon.isHidden == offline { setNeedsLayout() }
        }

        if options.homeHero {
            let info = SpotifyPlayback.info
            let pinned = info?.contextURI.map { uri in options.pinned.contains { $0.uri == uri } } ?? false
            hero.update(info, pinned: pinned, timing: info == nil ? nil : SpotifyPlayback.timing)
        }

        guard options.homeTiles else { return }
        for tile in tiles {
            switch tile.kind {
            case .sleep:
                switch SpotifyPlayback.sleepTimer {
                case .off: tile.setDetail(nil)
                case .endOfTrack: tile.setDetail("End of track")
                case .at(let date):
                    let minutes = max(0, Int(ceil(date.timeIntervalSinceNow / 60)))
                    tile.setDetail(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
                }
            case .queue:
                let next = SpotifyPlayback.upNextCount ?? 0
                tile.setDetail(next > 0 ? "\(next) next" : nil)
            case .downloads:
                tile.setDetail(offline ? "Offline" : nil)
                tile.setEmphasised(offline)
            default:
                break
            }
        }
    }

    private func togglePin() {
        guard let info = SpotifyPlayback.info, let uri = info.contextURI, !uri.isEmpty else { return }
        var options = UserDefaults.extrasOptions
        if let index = options.pinned.firstIndex(where: { $0.uri == uri }) {
            options.pinned.remove(at: index)
            Haptics.soft()
        } else {
            options.pinned.insert(PinnedItem(uri: uri, title: info.contextTitle ?? info.albumTitle ?? info.title), at: 0)
            Haptics.success()
        }
        UserDefaults.extrasOptions = options
        NotificationCenter.default.post(name: .eeveeExtrasChanged, object: nil)
    }

    private func rebuildPins() {
        let previous = Set(pinnedChips.map(\.item.uri))
        pinnedChips.forEach { $0.removeFromSuperview() }
        pinnedChips = options.pinned.map { item in
            let chip = PinChip(item)
            pinnedScroll.addSubview(chip)
            // New pins pop in; existing ones just move.
            if appeared, !previous.contains(item.uri) {
                chip.alpha = 0
                chip.transform = Style.reduceMotion ? .identity : CGAffineTransform(scaleX: 0.7, y: 0.7)
                Style.spring(0.05) {
                    chip.alpha = 1
                    chip.transform = .identity
                }
            }
            return chip
        }
    }
}

// MARK: - Glass

private func makeGlass(radius: CGFloat) -> UIVisualEffectView {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
        effect = UIGlassEffect(style: .regular)
    } else {
        effect = UIBlurEffect(style: .systemThinMaterialDark)
    }
    let view = UIVisualEffectView(effect: effect)
    view.overrideUserInterfaceStyle = .dark
    view.isUserInteractionEnabled = false
    if #available(iOS 26.0, *) {
        view.cornerConfiguration = .uniformCorners(radius: .fixed(radius))
    } else {
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
    }
    return view
}

private enum ArtworkCache {
    static let cache = NSCache<NSURL, UIImage>()

    static func load(_ url: URL, then done: @escaping (UIImage) -> Void) {
        if let image = cache.object(forKey: url as NSURL) { done(image); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async { done(image) }
        }.resume()
    }
}

private func topViewController(from view: UIView) -> UIViewController? {
    var controller = view.window?.rootViewController
    while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
    return controller
}

// A "go to" menu action that opens a Spotify URI in-app.
private func openAction(_ title: String, subtitle: String?, uri: String, symbol: String) -> UIAction {
    let action = UIAction(title: title, image: UIImage(systemName: symbol)) { _ in
        Haptics.tap()
        SpotifyNavigator.open(uri)
    }
    if #available(iOS 15.0, *), let subtitle, !subtitle.isEmpty { action.subtitle = subtitle }
    return action
}

// MARK: - Small parts

// Three bars that bounce while music plays and settle when it pauses.
private final class EqualizerBars: UIView {
    private let bars = (0..<3).map { _ in CALayer() }
    private var animating: Bool?
    private static let rest: [CGFloat] = [0.45, 0.8, 0.6]

    var color: UIColor = Style.green {
        didSet { bars.forEach { $0.backgroundColor = color.cgColor } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        bars.forEach {
            $0.cornerRadius = 1
            $0.anchorPoint = CGPoint(x: 0.5, y: 1)
            $0.backgroundColor = Style.green.cgColor
            layer.addSublayer($0)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width: CGFloat = 2.5, gap: CGFloat = 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(index) * (width + gap) + width / 2, y: bounds.height)
        }
        CATransaction.commit()
    }

    func set(playing: Bool, force: Bool = false) {
        let animate = playing && !Style.reduceMotion
        guard force || animating != animate else { return }
        animating = animate
        for (index, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            bar.transform = CATransform3DMakeScale(1, Self.rest[index], 1)
            guard animate else { continue }
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = 0.25
            bounce.toValue = 1
            bounce.duration = [0.42, 0.55, 0.48][index]
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bounce.timeOffset = Double(index) * 0.17
            bar.add(bounce, forKey: "bounce")
        }
    }
}

private final class ProgressTrack: UIView {
    private let fill = UIView()
    private(set) var fraction: CGFloat = 0

    var color: UIColor = .white { didSet { fill.backgroundColor = color } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(white: 1, alpha: 0.16)
        fill.backgroundColor = .white
        addSubview(fill)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        fill.layer.cornerRadius = bounds.height / 2
        placeFill()
    }

    private func placeFill() {
        fill.frame = CGRect(x: 0, y: 0, width: max(bounds.height, bounds.width * fraction), height: bounds.height)
        fill.alpha = fraction > 0 ? 1 : 0
    }

    // While playing, each one-second tick glides to the next value so the bar moves continuously.
    func set(_ value: CGFloat, glide: Bool) {
        let value = max(0, min(1, value))
        guard value != fraction else { return }
        let smooth = glide && value > fraction && value - fraction < 0.05
        fraction = value
        if smooth {
            UIView.animate(withDuration: 1, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) {
                self.placeFill()
            }
        } else {
            fill.layer.removeAllAnimations()
            placeFill()
        }
    }
}

private final class PlayButton: UIControl {
    private let disc = UIView()
    private let glyph = UIImageView()
    private var playing: Bool?

    override init(frame: CGRect) {
        super.init(frame: frame)
        disc.backgroundColor = .white
        disc.isUserInteractionEnabled = false
        addSubview(disc)
        glyph.tintColor = .black
        glyph.contentMode = .center
        disc.addSubview(glyph)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        Style.place(disc, bounds)
        disc.layer.cornerRadius = bounds.height / 2
        Style.place(glyph, CGRect(origin: .zero, size: bounds.size))
    }

    func set(playing: Bool) {
        guard playing != self.playing else { return }
        let first = self.playing == nil
        self.playing = playing
        accessibilityLabel = playing ? "Pause" : "Play"
        let image = Style.symbol(playing ? "pause.fill" : "play.fill", 19, .heavy)
        guard !first, window != nil else {
            glyph.image = image
            return
        }
        // The glyph swaps while shrinking and springs back: a soft morph between play and pause.
        UIView.transition(with: glyph, duration: 0.18, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.glyph.image = image
        }
        guard !Style.reduceMotion else { return }
        glyph.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.6,
                       options: [.allowUserInteraction]) { self.glyph.transform = .identity }
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.disc.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
    }

    @objc private func up() { Style.spring { self.disc.transform = .identity } }
}

private final class CapsuleButton: UIControl {
    private let glass = makeGlass(radius: 22)
    private let icon = UIImageView()
    private let label = UILabel()

    init(title: String, symbol: String, tint: UIColor) {
        super.init(frame: .zero)
        addSubview(glass)
        icon.image = Style.symbol(symbol, 14)
        icon.tintColor = tint
        icon.contentMode = .center
        addSubview(icon)
        label.text = title
        label.textColor = Style.primary
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        addSubview(label)
        applyFonts()
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyFonts() {
        label.font = Style.font(.subheadline, 14, .semibold, max: 18)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let text = label.sizeThatFits(CGSize(width: bounds.width - 44, height: bounds.height))
        let total = 18 + 6 + min(ceil(text.width), bounds.width - 44)
        let x = (bounds.width - total) / 2
        icon.frame = CGRect(x: x, y: 0, width: 18, height: bounds.height)
        label.frame = CGRect(x: x + 24, y: 0, width: total - 24, height: bounds.height)
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }

    @objc private func up() { Style.spring { self.transform = .identity } }
}

// MARK: - Hero card

private final class HeroCard: UIControl {
    var onPin: (() -> Void)?
    var actionsEnabled = true {
        didSet { isContextMenuInteractionEnabled = actionsEnabled }
    }
    var tintsFromArtwork = true {
        didSet { if oldValue != tintsFromArtwork { applyAccent(tintsFromArtwork ? artworkAccent : nil) } }
    }

    private let surface = UIView()
    private let backdrop = UIImageView()
    private let glass = makeGlass(radius: HeroCard.radius)
    private let wash = CAGradientLayer()
    private let artworkFrame = UIView()
    private let artwork = UIImageView()
    private let emptyGlyph = UIImageView()
    private let bars = EqualizerBars()
    private let overline = UILabel()
    private let title = UILabel()
    private let subtitle = UILabel()
    private let context = UILabel()
    private let pinButton = UIButton(type: .system)
    private let pinGlass = makeGlass(radius: 16)
    private let progress = ProgressTrack()
    private let elapsed = UILabel()
    private let remaining = UILabel()
    private let playButton = PlayButton()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let recentsButton = CapsuleButton(title: "Recents", symbol: "clock.arrow.circlepath",
                                              tint: UIColor(red: 0.35, green: 0.62, blue: 1, alpha: 1))
    private let likedButton = CapsuleButton(title: "Liked Songs", symbol: "heart.fill",
                                            tint: UIColor(red: 0.62, green: 0.48, blue: 1, alpha: 1))

    private var current: NowPlayingInfo?
    private var shownPinned: Bool?
    private var shownEmpty: Bool?
    private var shownArtwork: URL?
    private var artworkAccent: UIColor?

    static let radius: CGFloat = 26
    private static let pad: CGFloat = 16
    private static let artSide: CGFloat = 92
    private static let controlRow: CGFloat = 46

    static func preferredHeight(for width: CGFloat) -> CGFloat {
        let text = ceil(Style.font(.caption2, 11, .bold, max: 14).lineHeight)
            + ceil(Style.font(.title3, 19, .bold, rounded: true, max: 25).lineHeight)
            + ceil(Style.font(.subheadline, 14, .medium, max: 18).lineHeight)
            + ceil(Style.font(.footnote, 12, .medium, max: 15).lineHeight) + 10
        return pad + max(artSide, text) + 14 + controlRow + pad
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = Style.green.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: 10)

        surface.isUserInteractionEnabled = false
        surface.layer.cornerRadius = Self.radius
        surface.layer.cornerCurve = .continuous
        surface.layer.borderWidth = 1 / UIScreen.main.scale
        surface.layer.borderColor = Style.hairline.cgColor
        surface.clipsToBounds = true
        surface.backgroundColor = UIColor(white: 0.1, alpha: 1)
        addSubview(surface)

        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        surface.addSubview(backdrop)
        surface.addSubview(glass)
        wash.startPoint = CGPoint(x: 0, y: 0)
        wash.endPoint = CGPoint(x: 1, y: 1)
        surface.layer.addSublayer(wash)

        artworkFrame.isUserInteractionEnabled = false
        artworkFrame.layer.shadowColor = UIColor.black.cgColor
        artworkFrame.layer.shadowOpacity = 0.35
        artworkFrame.layer.shadowRadius = 10
        artworkFrame.layer.shadowOffset = CGSize(width: 0, height: 6)
        addSubview(artworkFrame)
        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 16
        artwork.layer.cornerCurve = .continuous
        artwork.backgroundColor = UIColor(white: 1, alpha: 0.08)
        artworkFrame.addSubview(artwork)
        emptyGlyph.contentMode = .center
        emptyGlyph.image = Style.symbol("music.note", 30, .semibold)
        emptyGlyph.tintColor = Style.green
        artwork.addSubview(emptyGlyph)

        addSubview(bars)
        overline.textColor = Style.secondary
        title.textColor = Style.primary
        subtitle.textColor = Style.secondary
        context.textColor = Style.tertiary
        elapsed.textColor = Style.tertiary
        remaining.textColor = Style.tertiary
        remaining.textAlignment = .right
        [overline, title, subtitle, context, elapsed, remaining].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        addSubview(progress)

        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        addSubview(playButton)
        configure(previousButton, "backward.fill", label: "Previous", action: #selector(previousTapped))
        configure(nextButton, "forward.fill", label: "Next", action: #selector(nextTapped))

        pinGlass.isUserInteractionEnabled = false
        addSubview(pinGlass)
        pinButton.tintColor = Style.primary
        pinButton.addTarget(self, action: #selector(pinTapped), for: .touchUpInside)
        addSubview(pinButton)

        recentsButton.addTarget(self, action: #selector(recentsTapped), for: .touchUpInside)
        likedButton.addTarget(self, action: #selector(likedTapped), for: .touchUpInside)
        addSubview(recentsButton)
        addSubview(likedButton)

        applyFonts()
        applyAccent(nil)
        isContextMenuInteractionEnabled = actionsEnabled
        addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ button: UIButton, _ symbol: String, label: String, action: Selector) {
        button.setImage(Style.symbol(symbol, 17, .heavy), for: .normal)
        button.tintColor = Style.primary
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        addSubview(button)
    }

    func applyFonts() {
        overline.font = Style.font(.caption2, 11, .bold, max: 14)
        title.font = Style.font(.title3, 19, .bold, rounded: true, max: 25)
        subtitle.font = Style.font(.subheadline, 14, .medium, max: 18)
        context.font = Style.font(.footnote, 12, .medium, max: 15)
        elapsed.font = Style.font(.caption2, 11, .semibold, monospacedDigits: true, max: 13)
        remaining.font = elapsed.font
        recentsButton.applyFonts()
        likedButton.applyFonts()
        setNeedsLayout()
    }

    func windowDidChange() {
        bars.set(playing: current.map { !$0.isPaused } ?? false, force: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad = Self.pad
        surface.frame = bounds
        // Oversized and blurred behind the glass, so the cover reads as colour, not as a picture.
        backdrop.frame = surface.bounds.insetBy(dx: -bounds.width * 0.3, dy: -bounds.height * 0.3)
        glass.frame = surface.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = surface.bounds
        CATransaction.commit()
        layer.shadowPath = UIBezierPath(roundedRect: bounds.insetBy(dx: 12, dy: 14), cornerRadius: Self.radius).cgPath

        let side = Self.artSide
        artworkFrame.frame = CGRect(x: pad, y: pad, width: side, height: side)
        artwork.frame = artworkFrame.bounds
        emptyGlyph.frame = artwork.bounds
        artworkFrame.layer.shadowPath = UIBezierPath(roundedRect: artworkFrame.bounds, cornerRadius: 16).cgPath

        let x = artworkFrame.frame.maxX + 14
        let w = bounds.width - x - pad
        pinGlass.frame = CGRect(x: bounds.width - pad - 28, y: pad - 4, width: 32, height: 32)
        pinButton.frame = pinGlass.frame.insetBy(dx: -6, dy: -6)
        let trailing = pinGlass.isHidden ? bounds.width - pad : pinGlass.frame.minX - 6

        var y = pad
        let overlineHeight = ceil(overline.font.lineHeight)
        bars.frame = CGRect(x: x, y: y + (overlineHeight - 10) / 2, width: 11.5, height: 10)
        let overlineX = bars.isHidden ? x : bars.frame.maxX + 6
        overline.frame = CGRect(x: overlineX, y: y, width: max(0, trailing - overlineX), height: overlineHeight)
        y += overlineHeight + 4
        let titleHeight = ceil(title.font.lineHeight)
        title.frame = CGRect(x: x, y: y, width: max(0, trailing - x), height: titleHeight)
        y += titleHeight + 2
        let subtitleHeight = ceil(subtitle.font.lineHeight)
        subtitle.frame = CGRect(x: x, y: y, width: w, height: subtitleHeight)
        y += subtitleHeight + 4
        context.frame = CGRect(x: x, y: y, width: w, height: ceil(context.font.lineHeight))

        // Bottom row: progress and times on the left, transport on the right; or, with nothing
        // playing, two shortcuts that start something.
        let rowY = bounds.height - pad - Self.controlRow
        let play: CGFloat = 46
        Style.place(playButton, CGRect(x: bounds.width - pad - play, y: rowY, width: play, height: play))
        nextButton.frame = CGRect(x: bounds.width - pad - play - 44, y: rowY + 3, width: 40, height: 40)
        previousButton.frame = CGRect(x: nextButton.frame.minX - 42, y: rowY + 3, width: 40, height: 40)
        let trackWidth = max(40, previousButton.frame.minX - pad - 10)
        let timeHeight = ceil(elapsed.font.lineHeight)
        let trackY = rowY + (Self.controlRow - 4 - 6 - timeHeight) / 2
        progress.frame = CGRect(x: pad, y: trackY, width: trackWidth, height: 4)
        elapsed.frame = CGRect(x: pad, y: trackY + 10, width: trackWidth / 2, height: timeHeight)
        remaining.frame = CGRect(x: pad + trackWidth / 2, y: trackY + 10, width: trackWidth / 2, height: timeHeight)

        let half = (bounds.width - pad * 2 - 10) / 2
        Style.place(recentsButton, CGRect(x: pad, y: rowY + 1, width: half, height: 44))
        Style.place(likedButton, CGRect(x: pad + half + 10, y: rowY + 1, width: half, height: 44))
    }

    func update(_ info: NowPlayingInfo?, pinned: Bool, timing: (position: Double, duration: Double)?) {
        updateProgress(info, timing)
        if info == current, pinned == shownPinned, shownEmpty == (info == nil) { return }
        let wasEmpty = shownEmpty
        let wasPinned = shownPinned
        current = info
        shownPinned = pinned
        shownEmpty = info == nil
        let empty = info == nil

        for view in [playButton, previousButton, nextButton, progress, elapsed, remaining] as [UIView] { view.isHidden = empty }
        recentsButton.isHidden = !empty
        likedButton.isHidden = !empty
        emptyGlyph.isHidden = !empty
        bars.isHidden = empty
        let canPin = !(info?.contextURI?.isEmpty ?? true)
        if pinButton.isHidden == canPin { setNeedsLayout() }
        pinButton.isHidden = !canPin
        pinGlass.isHidden = !canPin
        pinButton.setImage(Style.symbol(pinned ? "pin.fill" : "pin", 13), for: .normal)
        pinButton.accessibilityLabel = pinned ? "Unpin from Home" : "Pin to Home"
        if let wasPinned, wasPinned != pinned, !Style.reduceMotion {
            pinButton.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            Style.spring { self.pinButton.transform = .identity }
        }

        guard let info else {
            overline.text = "READY WHEN YOU ARE"
            title.text = "Nothing playing"
            subtitle.text = "Start something from your recents"
            context.text = nil
            artwork.image = nil
            shownArtwork = nil
            artworkAccent = nil
            if wasEmpty != true {
                UIView.transition(with: backdrop, duration: 0.3, options: .transitionCrossDissolve) { self.backdrop.image = nil }
                applyAccent(nil)
                setNeedsLayout()
            }
            return
        }

        overline.text = info.isPaused ? "PAUSED" : (info.isSpokenWord ? "LISTENING" : "NOW PLAYING")
        title.text = info.title
        subtitle.text = info.artist
        context.text = (info.contextTitle ?? info.albumTitle).map { "from \($0)" }
        playButton.set(playing: !info.isPaused)
        bars.set(playing: !info.isPaused)
        if wasEmpty != false { setNeedsLayout() }

        if let url = info.artworkURL {
            guard url != shownArtwork else { return }
            shownArtwork = url
            ArtworkCache.load(url) { [weak self] image in
                guard let self, self.shownArtwork == url else { return }
                self.show(image, key: url)
            }
        } else if let image = SpotifyPlayback.lockScreenArtwork {
            let key = URL(string: "lockscreen:" + (info.title.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))
            guard key != shownArtwork else { return }
            shownArtwork = key
            show(image, key: nil)
        }
    }

    private func updateProgress(_ info: NowPlayingInfo?, _ timing: (position: Double, duration: Double)?) {
        guard let info, let timing, timing.duration > 0 else {
            progress.set(0, glide: false)
            if elapsed.text != nil { elapsed.text = nil; remaining.text = nil }
            return
        }
        progress.set(CGFloat(timing.position / timing.duration), glide: !info.isPaused)
        elapsed.text = Style.time(timing.position)
        remaining.text = "-" + Style.time(timing.duration - timing.position)
        elapsed.accessibilityLabel = "\(Style.time(timing.position)) of \(Style.time(timing.duration))"
    }

    private func show(_ image: UIImage, key: URL?) {
        UIView.transition(with: artwork, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.artwork.image = image
        }
        UIView.transition(with: backdrop, duration: 0.5, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.backdrop.image = image
        }
        Accent.from(image, key: key) { [weak self] color in
            guard let self else { return }
            self.artworkAccent = color
            if self.tintsFromArtwork { self.applyAccent(color) }
        }
    }

    private func applyAccent(_ color: UIColor?) {
        let color = color ?? Style.green
        let strong = tintsFromArtwork && artworkAccent != nil
        let colors = [color.withAlphaComponent(strong ? 0.42 : 0.22).cgColor,
                      color.withAlphaComponent(0.08).cgColor,
                      UIColor.black.withAlphaComponent(0.32).cgColor]
        let fade = CABasicAnimation(keyPath: "colors")
        fade.fromValue = wash.colors
        fade.toValue = colors
        fade.duration = 0.6
        wash.colors = colors
        wash.add(fade, forKey: "colors")
        let glow = CABasicAnimation(keyPath: "shadowColor")
        glow.fromValue = layer.shadowColor
        glow.toValue = color.cgColor
        glow.duration = 0.6
        layer.shadowColor = color.cgColor
        layer.add(glow, forKey: "glow")
        bars.color = color
        progress.color = color
    }

    // MARK: Actions

    @objc private func playTapped() {
        Haptics.firm()
        SpotifyPlayback.togglePause()
        guard let info = current else { return }
        // Flip right away; the next tick confirms Spotify's real state.
        playButton.set(playing: info.isPaused)
        bars.set(playing: info.isPaused)
    }

    @objc private func previousTapped() { Haptics.soft(); SpotifyPlayback.previous() }
    @objc private func nextTapped() { Haptics.soft(); SpotifyPlayback.next() }
    @objc private func pinTapped() { onPin?() }
    @objc private func recentsTapped() { Haptics.tap(); SpotifyNavigator.open("spotify:recently-played") }
    @objc private func likedTapped() { Haptics.tap(); SpotifyNavigator.open("spotify:collection:tracks") }

    @objc private func cardTapped() {
        Haptics.tap()
        if let uri = current?.contextURI, !uri.isEmpty {
            SpotifyNavigator.open(uri)
        } else if let uri = current?.albumURI {
            SpotifyNavigator.open(uri)
        } else {
            SpotifyNavigator.open("spotify:recently-played")
        }
    }

    @objc private func pressDown() {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        }
    }

    @objc private func pressUp() { Style.spring { self.transform = .identity } }

    // MARK: Quick actions (long press)

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard actionsEnabled, let info = current else { return nil }
        let pinned = shownPinned ?? false
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var share: [UIMenuElement] = []
            if let uri = info.trackURI, let link = SpotifyNavigator.webLink(uri) {
                share.append(UIAction(title: "Share Song", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.share(link)
                })
                share.append(UIAction(title: "Copy Song Link", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.url = link
                    Haptics.success()
                })
            }
            var go: [UIMenuElement] = []
            if let uri = info.artistURI {
                go.append(openAction("Go to Artist", subtitle: info.artist, uri: uri, symbol: "person.crop.circle"))
            }
            if let uri = info.albumURI {
                go.append(openAction("Go to Album", subtitle: info.albumTitle, uri: uri, symbol: "square.stack"))
            }
            if let uri = info.contextURI, !uri.isEmpty, uri != info.albumURI {
                go.append(openAction("Open \(info.contextTitle ?? "Playlist")", subtitle: nil, uri: uri, symbol: "music.note.list"))
            }
            go.append(openAction("Queue", subtitle: nil, uri: "spotify:internal:now-playing-queue", symbol: "list.bullet"))
            var more: [UIMenuElement] = []
            if let uri = info.contextURI, !uri.isEmpty {
                more.append(UIAction(title: pinned ? "Unpin from Home" : "Pin to Home",
                                     image: UIImage(systemName: pinned ? "pin.slash" : "pin")) { _ in self?.onPin?() })
            }
            let sections = [share, go, more].filter { !$0.isEmpty }.map {
                UIMenu(title: "", options: .displayInline, children: $0)
            }
            return UIMenu(title: "", children: sections)
        }
    }

    private func share(_ link: URL) {
        guard let presenter = topViewController(from: self) else { return }
        let sheet = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = self
        sheet.popoverPresentationController?.sourceRect = bounds
        presenter.present(sheet, animated: true)
    }
}

// MARK: - Tiles

private final class HomeTile: UIControl {
    enum Kind: CaseIterable {
        case liked, downloads, recents, queue, sleep, equalizer

        var order: Int { Kind.allCases.firstIndex(of: self) ?? 0 }

        var title: String {
            switch self {
            case .liked: return "Liked Songs"
            case .downloads: return "Downloads"
            case .recents: return "Recents"
            case .queue: return "Queue"
            case .sleep: return "Sleep timer"
            case .equalizer: return "Equalizer"
            }
        }

        var symbol: String {
            switch self {
            case .liked: return "heart.fill"
            case .downloads: return "arrow.down.circle.fill"
            case .recents: return "clock.arrow.circlepath"
            case .queue: return "list.bullet"
            case .sleep: return "moon.zzz.fill"
            case .equalizer: return "slider.vertical.3"
            }
        }

        var tint: UIColor {
            switch self {
            case .liked: return UIColor(red: 0.55, green: 0.42, blue: 1, alpha: 1)
            case .downloads: return Style.green
            case .recents: return UIColor(red: 0.27, green: 0.56, blue: 1, alpha: 1)
            case .queue: return UIColor(red: 1, green: 0.58, blue: 0.2, alpha: 1)
            case .sleep: return UIColor(red: 0.45, green: 0.45, blue: 0.98, alpha: 1)
            case .equalizer: return UIColor(red: 1, green: 0.36, blue: 0.56, alpha: 1)
            }
        }

        var uri: String {
            switch self {
            case .liked: return "spotify:collection:tracks"
            case .downloads: return "spotify:collection:downloads"
            case .recents: return "spotify:recently-played"
            case .queue: return "spotify:internal:now-playing-queue"
            case .sleep: return "spotify:internal:sleepTimer"
            case .equalizer: return "spotify:internal:equalizer"
            }
        }
    }

    static var preferredHeight: CGFloat {
        max(78, 12 + 30 + 8 + ceil(Style.font(.footnote, 13, .semibold, max: 16).lineHeight) + 10)
    }

    let kind: Kind
    private let glass = makeGlass(radius: 20)
    private let highlight = UIView()
    private let iconWell = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let detail = UILabel()
    private var emphasised = false

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        addSubview(glass)
        highlight.isUserInteractionEnabled = false
        highlight.layer.cornerRadius = 20
        highlight.layer.cornerCurve = .continuous
        highlight.layer.borderColor = kind.tint.cgColor
        highlight.backgroundColor = kind.tint.withAlphaComponent(0.14)
        highlight.alpha = 0
        addSubview(highlight)

        // An app-icon style squircle: solid colour, white glyph.
        iconWell.backgroundColor = kind.tint
        iconWell.layer.cornerRadius = 9
        iconWell.layer.cornerCurve = .continuous
        iconWell.isUserInteractionEnabled = false
        addSubview(iconWell)
        icon.image = Style.symbol(kind.symbol, 14)
        icon.tintColor = .white
        icon.contentMode = .center
        iconWell.addSubview(icon)

        label.text = kind.title
        label.textColor = Style.primary
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        addSubview(label)
        detail.textColor = kind.tint
        detail.textAlignment = .right
        detail.adjustsFontSizeToFitWidth = true
        detail.minimumScaleFactor = 0.8
        detail.isHidden = true
        addSubview(detail)
        applyFonts()

        accessibilityLabel = kind.title
        isAccessibilityElement = true
        accessibilityTraits = .button

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyFonts() {
        label.font = Style.font(.footnote, 13, .semibold, max: 16)
        detail.font = Style.font(.caption2, 11, .bold, monospacedDigits: true, max: 13)
        setNeedsLayout()
    }

    func setDetail(_ text: String?) {
        guard detail.text != text else { return }
        let appearing = detail.isHidden && text != nil
        detail.text = text
        detail.isHidden = text == nil
        accessibilityValue = text
        if appearing, window != nil {
            detail.alpha = 0
            UIView.animate(withDuration: 0.25) { self.detail.alpha = 1 }
        }
        setNeedsLayout()
    }

    func setEmphasised(_ on: Bool) {
        guard on != emphasised else { return }
        emphasised = on
        highlight.layer.borderWidth = on ? 1.5 : 0
        UIView.animate(withDuration: 0.3) { self.highlight.alpha = on ? 1 : 0 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        highlight.frame = bounds
        iconWell.frame = CGRect(x: 12, y: 12, width: 30, height: 30)
        icon.frame = iconWell.bounds
        detail.frame = CGRect(x: iconWell.frame.maxX + 6, y: 12, width: max(0, bounds.width - iconWell.frame.maxX - 16), height: 30)
        let labelHeight = ceil(label.font.lineHeight)
        label.frame = CGRect(x: 12, y: bounds.height - 10 - labelHeight, width: bounds.width - 22, height: labelHeight)
    }

    @objc private func tapped() {
        Haptics.tap()
        SpotifyNavigator.open(kind.uri)
    }

    @objc private func pressDown() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
    }

    @objc private func pressUp() { Style.spring { self.transform = .identity } }
}

// MARK: - Pinned chips

private final class PinChip: UIControl {
    static let height: CGFloat = 42

    let item: PinnedItem
    private let glass = makeGlass(radius: PinChip.height / 2)
    private let well = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    init(_ item: PinnedItem) {
        self.item = item
        super.init(frame: .zero)
        addSubview(glass)
        let tint = Self.tint(for: item.uri)
        well.backgroundColor = tint.withAlphaComponent(0.22)
        well.isUserInteractionEnabled = false
        addSubview(well)
        icon.image = Style.symbol(Self.symbol(for: item.uri), 12)
        icon.tintColor = tint
        icon.contentMode = .center
        well.addSubview(icon)
        label.text = item.title
        label.textColor = Style.primary
        addSubview(label)
        applyFonts()
        accessibilityLabel = item.title
        accessibilityHint = "Long-press for options"
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(down), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(up), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        isContextMenuInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyFonts() {
        label.font = Style.font(.subheadline, 14, .semibold, max: 17)
        setNeedsLayout()
    }

    private static func symbol(for uri: String) -> String {
        if uri.contains(":collection") { return "heart.fill" }
        if uri.contains(":album:") { return "square.stack.fill" }
        if uri.contains(":artist:") { return "person.fill" }
        if uri.contains(":show:") || uri.contains(":episode:") { return "mic.fill" }
        return "music.note.list"
    }

    private static func tint(for uri: String) -> UIColor {
        if uri.contains(":collection") { return UIColor(red: 0.62, green: 0.5, blue: 1, alpha: 1) }
        if uri.contains(":album:") { return UIColor(red: 1, green: 0.62, blue: 0.3, alpha: 1) }
        if uri.contains(":artist:") { return UIColor(red: 0.35, green: 0.65, blue: 1, alpha: 1) }
        if uri.contains(":show:") || uri.contains(":episode:") { return UIColor(red: 0.2, green: 0.8, blue: 0.75, alpha: 1) }
        return Style.green
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(CGSize(width: size.width - 56, height: Self.height))
        return CGSize(width: min(size.width, ceil(text.width) + 56), height: Self.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        well.frame = CGRect(x: 6, y: 6, width: bounds.height - 12, height: bounds.height - 12)
        well.layer.cornerRadius = well.bounds.height / 2
        icon.frame = well.bounds
        label.frame = CGRect(x: well.frame.maxX + 8, y: 0, width: max(0, bounds.width - well.frame.maxX - 22), height: bounds.height)
    }

    @objc private func tapped() {
        Haptics.tap()
        SpotifyNavigator.open(item.uri)
    }

    @objc private func down() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }
    }

    @objc private func up() { Style.spring { self.transform = .identity } }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let uri = item.uri
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            func edit(_ change: @escaping (inout [PinnedItem]) -> Void) {
                var options = UserDefaults.extrasOptions
                change(&options.pinned)
                UserDefaults.extrasOptions = options
                NotificationCenter.default.post(name: .eeveeExtrasChanged, object: nil)
            }
            var actions: [UIMenuElement] = [
                UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right")) { _ in SpotifyNavigator.open(uri) },
            ]
            if let link = SpotifyNavigator.webLink(uri) {
                actions.append(UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.url = link
                    Haptics.success()
                })
            }
            if UserDefaults.extrasOptions.pinned.first?.uri != uri {
                actions.append(UIAction(title: "Move to Front", image: UIImage(systemName: "arrow.left.to.line")) { _ in
                    edit { pins in
                        guard let index = pins.firstIndex(where: { $0.uri == uri }) else { return }
                        pins.insert(pins.remove(at: index), at: 0)
                    }
                })
            }
            actions.append(UIAction(title: "Unpin", image: UIImage(systemName: "pin.slash"), attributes: .destructive) { _ in
                edit { $0.removeAll { $0.uri == uri } }
            })
            return UIMenu(children: actions)
        }
    }
}
