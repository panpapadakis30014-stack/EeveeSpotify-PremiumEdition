import Orion
import UIKit

// Eevee Home: a reimagined top of the Home tab. A greeting, a "now playing" hero card
// built from the current track's artwork, one-tap glass tiles for the places people
// actually go (Liked Songs, Downloads, Recents, Queue, Sleep timer, Equalizer) and a
// row of pinned playlists/albums. Spotify's own shelves carry on underneath.
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

// MARK: - Header

final class EeveeHomeHeader: UIView {
    private let greeting = UILabel()
    private let dateLine = UILabel()
    private let hero = HeroCard()
    private var tiles: [HomeTile] = []
    private let pinnedTitle = UILabel()
    private let pinnedScroll = UIScrollView()
    private var pinnedChips: [PinChip] = []
    private var options = UserDefaults.extrasOptions
    private var ticker: Timer?

    private static let margin: CGFloat = 16
    private static let greetingHeight: CGFloat = 62
    private static let heroHeight: CGFloat = 128
    private static let tileHeight: CGFloat = 66
    private static let gap: CGFloat = 14
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false

        greeting.font = .systemFont(ofSize: 30, weight: .heavy).rounded
        greeting.textColor = .white
        greeting.adjustsFontSizeToFitWidth = true
        greeting.minimumScaleFactor = 0.7
        dateLine.font = .systemFont(ofSize: 13, weight: .semibold)
        dateLine.textColor = UIColor.white.withAlphaComponent(0.6)
        addSubview(greeting)
        addSubview(dateLine)

        hero.onPin = { [weak self] in self?.togglePin() }
        addSubview(hero)

        tiles = HomeTile.Kind.allCases.map { kind in
            let tile = HomeTile(kind)
            addSubview(tile)
            return tile
        }

        pinnedTitle.text = "Pinned"
        pinnedTitle.font = .systemFont(ofSize: 17, weight: .bold).rounded
        pinnedTitle.textColor = .white
        addSubview(pinnedTitle)
        pinnedScroll.showsHorizontalScrollIndicator = false
        pinnedScroll.alwaysBounceHorizontal = true
        pinnedScroll.clipsToBounds = false
        addSubview(pinnedScroll)
        rebuildPins()

        NotificationCenter.default.addObserver(self, selector: #selector(optionsChanged), name: .eeveeExtrasChanged, object: nil)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        ticker?.invalidate()
        ticker = nil
        guard window != nil else { return }
        refresh()
        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        tick.tolerance = 0.3
        RunLoop.main.add(tick, forMode: .common)
        ticker = tick
    }

    @objc private func optionsChanged() {
        options = UserDefaults.extrasOptions
        rebuildPins()
        setNeedsLayout()
        // Let the page recompute its inset for the new height.
        superview?.superview?.setNeedsLayout()
        superview?.setNeedsLayout()
    }

    private var showsPins: Bool { !options.pinned.isEmpty }

    func preferredHeight(for width: CGFloat) -> CGFloat {
        var height: CGFloat = 6
        if options.homeGreeting { height += Self.greetingHeight + 4 }
        if options.homeHero { height += Self.heroHeight + Self.gap }
        if options.homeTiles { height += Self.tileHeight * 2 + 8 + Self.gap }
        if showsPins { height += 28 + 44 + Self.gap }
        return height + 6
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let m = Self.margin
        let w = bounds.width - m * 2
        var y: CGFloat = 6

        greeting.isHidden = !options.homeGreeting
        dateLine.isHidden = !options.homeGreeting
        if options.homeGreeting {
            greeting.frame = CGRect(x: m, y: y, width: w, height: 38)
            dateLine.frame = CGRect(x: m, y: y + 38, width: w, height: 20)
            y += Self.greetingHeight + 4
        }

        hero.isHidden = !options.homeHero
        if options.homeHero {
            hero.frame = CGRect(x: m, y: y, width: w, height: Self.heroHeight)
            y += Self.heroHeight + Self.gap
        }

        tiles.forEach { $0.isHidden = !options.homeTiles }
        if options.homeTiles {
            let columns: CGFloat = 3
            let spacing: CGFloat = 8
            let tileWidth = (w - spacing * (columns - 1)) / columns
            for (index, tile) in tiles.enumerated() {
                let row = CGFloat(index / 3), column = CGFloat(index % 3)
                tile.frame = CGRect(x: m + column * (tileWidth + spacing), y: y + row * (Self.tileHeight + spacing),
                                    width: tileWidth, height: Self.tileHeight)
            }
            y += Self.tileHeight * 2 + spacing + Self.gap
        }

        pinnedTitle.isHidden = !showsPins
        pinnedScroll.isHidden = !showsPins
        if showsPins {
            pinnedTitle.frame = CGRect(x: m, y: y, width: w, height: 24)
            pinnedScroll.frame = CGRect(x: 0, y: y + 28, width: bounds.width, height: 40)
            var x = m
            for chip in pinnedChips {
                let size = chip.sizeThatFits(CGSize(width: 220, height: 40))
                chip.frame = CGRect(x: x, y: 0, width: size.width, height: 40)
                x += size.width + 8
            }
            pinnedScroll.contentSize = CGSize(width: x + m - 8, height: 40)
        }
    }

    // MARK: Content

    private func refresh() {
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
            let date = Self.dateFormatter.string(from: Date())
            if dateLine.text != date { dateLine.text = date }
        }

        let info = options.homeHero ? SpotifyPlayback.info : nil
        if options.homeHero {
            hero.update(info, pinned: info?.contextURI.map { uri in options.pinned.contains { $0.uri == uri } } ?? false)
        }

        if options.homeTiles, let sleep = tiles.first(where: { $0.kind == .sleep }) {
            switch SpotifyPlayback.sleepTimer {
            case .off: sleep.setDetail(nil)
            case .endOfTrack: sleep.setDetail("End of track")
            case .at(let date):
                let minutes = max(0, Int(ceil(date.timeIntervalSinceNow / 60)))
                sleep.setDetail(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
            }
        }
    }

    private func togglePin() {
        guard let info = SpotifyPlayback.info, let uri = info.contextURI, !uri.isEmpty else { return }
        var options = UserDefaults.extrasOptions
        if let index = options.pinned.firstIndex(where: { $0.uri == uri }) {
            options.pinned.remove(at: index)
        } else {
            options.pinned.insert(PinnedItem(uri: uri, title: info.contextTitle ?? info.title), at: 0)
        }
        UserDefaults.extrasOptions = options
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        NotificationCenter.default.post(name: .eeveeExtrasChanged, object: nil)
    }

    private func rebuildPins() {
        pinnedChips.forEach { $0.removeFromSuperview() }
        pinnedChips = options.pinned.map { item in
            let chip = PinChip(item)
            pinnedScroll.addSubview(chip)
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

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

private enum ArtworkCache {
    static let cache = NSCache<NSURL, UIImage>()

    static func load(_ url: URL, into view: UIImageView, then done: @escaping (UIImage) -> Void) {
        if let image = cache.object(forKey: url as NSURL) { done(image); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            cache.setObject(image, forKey: url as NSURL)
            DispatchQueue.main.async { done(image) }
        }.resume()
    }
}

// MARK: - Hero card

private final class HeroCard: UIControl {
    var onPin: (() -> Void)?

    private let backdrop = UIImageView()
    private let glass = makeGlass(radius: 24)
    private let shade = UIView()
    private let artwork = UIImageView()
    private let overline = UILabel()
    private let title = UILabel()
    private let subtitle = UILabel()
    private let context = UILabel()
    private let playButton = UIButton(type: .system)
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let pinButton = UIButton(type: .system)
    private var shownArtwork: URL?
    private var current: NowPlayingInfo?
    private var shownPinned: Bool?
    private var shownEmpty = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = UIColor(white: 0.12, alpha: 1)

        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.isUserInteractionEnabled = false
        backdrop.transform = CGAffineTransform(scaleX: 1.6, y: 1.6)
        addSubview(backdrop)
        addSubview(glass)
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        shade.isUserInteractionEnabled = false
        addSubview(shade)

        artwork.contentMode = .scaleAspectFill
        artwork.clipsToBounds = true
        artwork.layer.cornerRadius = 14
        artwork.layer.cornerCurve = .continuous
        artwork.backgroundColor = UIColor(white: 1, alpha: 0.08)
        artwork.isUserInteractionEnabled = false
        addSubview(artwork)

        overline.font = .systemFont(ofSize: 11, weight: .bold)
        overline.textColor = UIColor.white.withAlphaComponent(0.7)
        title.font = .systemFont(ofSize: 18, weight: .bold).rounded
        title.textColor = .white
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = UIColor.white.withAlphaComponent(0.75)
        context.font = .systemFont(ofSize: 12, weight: .medium)
        context.textColor = UIColor.white.withAlphaComponent(0.55)
        [overline, title, subtitle, context].forEach { $0.isUserInteractionEnabled = false; addSubview($0) }

        configure(playButton, "play.fill", size: 18, action: #selector(playTapped))
        playButton.backgroundColor = .white
        playButton.tintColor = .black
        playButton.layer.cornerRadius = 21
        configure(previousButton, "backward.fill", size: 16, action: #selector(previousTapped))
        configure(nextButton, "forward.fill", size: 16, action: #selector(nextTapped))
        configure(pinButton, "pin", size: 14, action: #selector(pinTapped))
        pinButton.tintColor = UIColor.white.withAlphaComponent(0.8)

        addTarget(self, action: #selector(cardTapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func configure(_ button: UIButton, _ symbol: String, size: CGFloat, action: Selector) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .bold)), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        addSubview(button)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        glass.frame = bounds
        shade.frame = bounds
        let pad: CGFloat = 16
        let side = bounds.height - pad * 2
        artwork.frame = CGRect(x: pad, y: pad, width: side, height: side)
        let x = artwork.frame.maxX + 14
        let w = bounds.width - x - pad
        pinButton.frame = CGRect(x: bounds.width - 40, y: 8, width: 32, height: 32)
        overline.frame = CGRect(x: x, y: pad, width: w - 28, height: 14)
        title.frame = CGRect(x: x, y: pad + 16, width: w, height: 24)
        subtitle.frame = CGRect(x: x, y: pad + 40, width: w, height: 18)
        context.frame = CGRect(x: x, y: pad + 58, width: w - 120, height: 16)
        let controlsY = bounds.height - pad - 42
        playButton.frame = CGRect(x: bounds.width - pad - 42, y: controlsY, width: 42, height: 42)
        nextButton.frame = CGRect(x: playButton.frame.minX - 40, y: controlsY + 3, width: 36, height: 36)
        previousButton.frame = CGRect(x: nextButton.frame.minX - 38, y: controlsY + 3, width: 36, height: 36)
        context.frame.size.width = max(40, previousButton.frame.minX - x - 6)
        context.frame.origin.y = controlsY + 13
    }

    func update(_ info: NowPlayingInfo?, pinned: Bool) {
        if info == current, pinned == shownPinned, info != nil || shownEmpty { return }
        current = info
        shownPinned = pinned
        shownEmpty = info == nil
        let playing = info != nil
        [playButton, previousButton, nextButton].forEach { $0.isHidden = !playing }
        pinButton.isHidden = info?.contextURI?.isEmpty ?? true
        pinButton.setImage(UIImage(systemName: pinned ? "pin.fill" : "pin",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)), for: .normal)

        guard let info else {
            overline.text = "NOTHING PLAYING"
            title.text = "Pick up where you left off"
            subtitle.text = "Tap to open your recents"
            context.text = nil
            artwork.image = UIImage(systemName: "clock.arrow.circlepath", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))
            artwork.contentMode = .center
            artwork.tintColor = UIColor.white.withAlphaComponent(0.6)
            backdrop.image = nil
            shownArtwork = nil
            return
        }

        overline.text = info.isPaused ? "PAUSED" : "NOW PLAYING"
        title.text = info.title
        subtitle.text = info.artist
        context.text = info.contextTitle.map { "from \($0)" }
        playButton.setImage(UIImage(systemName: info.isPaused ? "play.fill" : "pause.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)), for: .normal)

        if let url = info.artworkURL {
            guard url != shownArtwork else { return }
            shownArtwork = url
            ArtworkCache.load(url, into: artwork) { [weak self] image in
                guard let self, self.shownArtwork == url else { return }
                self.show(image)
            }
        } else if let image = SpotifyPlayback.lockScreenArtwork {
            shownArtwork = URL(string: "lockscreen:\(info.title)")
            show(image)
        }
    }

    private func show(_ image: UIImage) {
        artwork.contentMode = .scaleAspectFill
        UIView.transition(with: self, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.artwork.image = image
            self.backdrop.image = image
        }
    }

    @objc private func playTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SpotifyPlayback.togglePause()
    }

    @objc private func previousTapped() { SpotifyPlayback.previous() }
    @objc private func nextTapped() { SpotifyPlayback.next() }
    @objc private func pinTapped() { onPin?() }

    @objc private func cardTapped() {
        if let uri = current?.contextURI, !uri.isEmpty {
            SpotifyNavigator.open(uri)
        } else {
            SpotifyNavigator.open("spotify:recently-played")
        }
    }

    @objc private func pressDown() {
        UIView.animate(withDuration: 0.15) { self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98) }
    }

    @objc private func pressUp() {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) { self.transform = .identity }
    }
}

// MARK: - Tiles

private final class HomeTile: UIControl {
    enum Kind: CaseIterable {
        case liked, downloads, recents, queue, sleep, equalizer

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
            case .liked: return UIColor(red: 0.62, green: 0.48, blue: 1, alpha: 1)
            case .downloads: return UIColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1)
            case .recents: return UIColor(red: 0.35, green: 0.62, blue: 1, alpha: 1)
            case .queue: return UIColor(red: 1, green: 0.62, blue: 0.25, alpha: 1)
            case .sleep: return UIColor(red: 0.55, green: 0.55, blue: 1, alpha: 1)
            case .equalizer: return UIColor(red: 1, green: 0.42, blue: 0.62, alpha: 1)
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

    let kind: Kind
    private let glass = makeGlass(radius: 18)
    private let iconWell = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let detail = UILabel()

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        addSubview(glass)
        iconWell.backgroundColor = kind.tint.withAlphaComponent(0.22)
        iconWell.layer.cornerRadius = 13
        iconWell.isUserInteractionEnabled = false
        addSubview(iconWell)
        icon.image = UIImage(systemName: kind.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        icon.tintColor = kind.tint
        icon.contentMode = .center
        iconWell.addSubview(icon)
        label.text = kind.title
        label.font = .systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        addSubview(label)
        detail.font = .systemFont(ofSize: 11, weight: .semibold)
        detail.textColor = kind.tint
        detail.isHidden = true
        addSubview(detail)
        accessibilityLabel = kind.title
        isAccessibilityElement = true
        accessibilityTraits = .button

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setDetail(_ text: String?) {
        guard detail.text != text else { return }
        detail.text = text
        detail.isHidden = text == nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        iconWell.frame = CGRect(x: 10, y: 10, width: 26, height: 26)
        icon.frame = iconWell.bounds
        if detail.isHidden {
            label.frame = CGRect(x: 10, y: bounds.height - 26, width: bounds.width - 20, height: 18)
        } else {
            detail.frame = CGRect(x: 42, y: 14, width: bounds.width - 48, height: 16)
            label.frame = CGRect(x: 10, y: bounds.height - 26, width: bounds.width - 20, height: 18)
        }
    }

    @objc private func tapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SpotifyNavigator.open(kind.uri)
    }

    @objc private func pressDown() {
        UIView.animate(withDuration: 0.12) { self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95) }
    }

    @objc private func pressUp() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0) { self.transform = .identity }
    }
}

// MARK: - Pinned chips

private final class PinChip: UIControl {
    private let item: PinnedItem
    private let glass = makeGlass(radius: 20)
    private let icon = UIImageView()
    private let label = UILabel()

    init(_ item: PinnedItem) {
        self.item = item
        super.init(frame: .zero)
        addSubview(glass)
        icon.image = UIImage(systemName: Self.symbol(for: item.uri), withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        icon.tintColor = UIColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1)
        icon.contentMode = .center
        addSubview(icon)
        label.text = item.title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        addSubview(label)
        accessibilityLabel = item.title
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isContextMenuInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func symbol(for uri: String) -> String {
        if uri.contains(":collection") { return "heart.fill" }
        if uri.contains(":album:") { return "square.stack.fill" }
        if uri.contains(":artist:") { return "person.fill" }
        if uri.contains(":show:") || uri.contains(":episode:") { return "mic.fill" }
        return "music.note.list"
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let text = label.sizeThatFits(CGSize(width: size.width - 46, height: 20))
        return CGSize(width: min(size.width, text.width + 46), height: 40)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        icon.frame = CGRect(x: 10, y: 0, width: 20, height: bounds.height)
        label.frame = CGRect(x: 32, y: 0, width: bounds.width - 46, height: bounds.height)
    }

    @objc private func tapped() {
        SpotifyNavigator.open(item.uri)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        let uri = item.uri
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            UIMenu(children: [
                UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right")) { _ in SpotifyNavigator.open(uri) },
                UIAction(title: "Unpin", image: UIImage(systemName: "pin.slash"), attributes: .destructive) { _ in
                    var options = UserDefaults.extrasOptions
                    options.pinned.removeAll { $0.uri == uri }
                    UserDefaults.extrasOptions = options
                    NotificationCenter.default.post(name: .eeveeExtrasChanged, object: nil)
                },
            ])
        }
    }
}
