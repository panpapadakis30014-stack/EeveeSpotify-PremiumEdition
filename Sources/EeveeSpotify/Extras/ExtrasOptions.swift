import Foundation

// Premium Edition extras. Every option here is purely client-side
// (UI / playback convenience) and never touches account entitlements.

enum StartupPage: String, Codable, CaseIterable {
    case home, search, library

    var uri: String? {
        switch self {
        case .home:    return nil
        case .search:  return "spotify:search"
        case .library: return "spotify:collection"
        }
    }

    var title: String {
        switch self {
        case .home:    return "Home"
        case .search:  return "Search"
        case .library: return "Your Library"
        }
    }
}

// The sections of Eevee Home, in the order the user chose.
enum HomeSection: String, Codable, CaseIterable, Hashable {
    case greeting, nowPlaying, shortcuts, recents, pinned, stats

    var title: String {
        switch self {
        case .greeting: return "Greeting"
        case .nowPlaying: return "Now playing card"
        case .shortcuts: return "Quick tiles"
        case .recents: return "Jump back in"
        case .pinned: return "Pinned"
        case .stats: return "Your listening"
        }
    }

    var icon: String {
        switch self {
        case .greeting: return "sun.max.fill"
        case .nowPlaying: return "play.rectangle.fill"
        case .shortcuts: return "square.grid.3x2.fill"
        case .recents: return "clock.arrow.circlepath"
        case .pinned: return "pin.fill"
        case .stats: return "chart.bar.fill"
        }
    }
}

// Something pinned to the top of the Eevee Home header (a playlist, album, artist…).
struct PinnedItem: Codable, Equatable, Hashable {
    var uri: String
    var title: String
}

struct ExtrasOptions: Codable, Equatable {
    var startupPage = StartupPage.home

    // Eevee Home: the reimagined header at the top of Home.
    var eeveeHome = true
    var homeGreeting = true
    var homeHero = true
    var homeTiles = true
    var pinned: [PinnedItem] = []
    var homeRecents = true
    var homePinned = true
    var homeStats = true
    var homeOrder = HomeSection.allCases
    var homeArtworkTint = true
    var homeHaptics = true
    var heroActions = true

    // Sleep timer: fade out before Spotify's own timer pauses playback.
    var sleepFade = true
    var sleepFadeSeconds = 60

    // Music-only mode for Home.
    var hidePodcasts = false

    // Quality of life.
    var resumeOnLaunch = false
    var resumeNeedsHeadphones = true
    var awakeWhileCharging = false
    var offlineOpensDownloads = false
    // Jump back in + listening stats are built from this on-device log.
    var recordListening = true
    var lyricsAwake = true
    var tabHaptics = true

    // Every section once, in the saved order, with any new section appended.
    var orderedSections: [HomeSection] {
        var seen = Set<HomeSection>()
        let saved = homeOrder.filter { seen.insert($0).inserted }
        return saved + HomeSection.allCases.filter { !seen.contains($0) }
    }

    func shows(_ section: HomeSection) -> Bool {
        switch section {
        case .greeting: return homeGreeting
        case .nowPlaying: return homeHero
        case .shortcuts: return homeTiles
        case .recents: return homeRecents && recordListening
        case .pinned: return homePinned
        case .stats: return homeStats && recordListening
        }
    }

    static let fadeChoices = [15, 30, 60, 120, 300]
    // What this launch is running with (settings changes apply after a restart).
    static let launch = UserDefaults.extrasOptions

    init() {}

    // Keep decoding settings saved by older builds when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExtrasOptions()
        startupPage = try c.decodeIfPresent(StartupPage.self, forKey: .startupPage) ?? d.startupPage
        eeveeHome = try c.decodeIfPresent(Bool.self, forKey: .eeveeHome) ?? d.eeveeHome
        homeGreeting = try c.decodeIfPresent(Bool.self, forKey: .homeGreeting) ?? d.homeGreeting
        homeHero = try c.decodeIfPresent(Bool.self, forKey: .homeHero) ?? d.homeHero
        homeTiles = try c.decodeIfPresent(Bool.self, forKey: .homeTiles) ?? d.homeTiles
        pinned = try c.decodeIfPresent([PinnedItem].self, forKey: .pinned) ?? d.pinned
        sleepFade = try c.decodeIfPresent(Bool.self, forKey: .sleepFade) ?? d.sleepFade
        sleepFadeSeconds = try c.decodeIfPresent(Int.self, forKey: .sleepFadeSeconds) ?? d.sleepFadeSeconds
        hidePodcasts = try c.decodeIfPresent(Bool.self, forKey: .hidePodcasts) ?? d.hidePodcasts
        homeArtworkTint = try c.decodeIfPresent(Bool.self, forKey: .homeArtworkTint) ?? d.homeArtworkTint
        homeHaptics = try c.decodeIfPresent(Bool.self, forKey: .homeHaptics) ?? d.homeHaptics
        heroActions = try c.decodeIfPresent(Bool.self, forKey: .heroActions) ?? d.heroActions
        resumeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .resumeOnLaunch) ?? d.resumeOnLaunch
        resumeNeedsHeadphones = try c.decodeIfPresent(Bool.self, forKey: .resumeNeedsHeadphones) ?? d.resumeNeedsHeadphones
        awakeWhileCharging = try c.decodeIfPresent(Bool.self, forKey: .awakeWhileCharging) ?? d.awakeWhileCharging
        offlineOpensDownloads = try c.decodeIfPresent(Bool.self, forKey: .offlineOpensDownloads) ?? d.offlineOpensDownloads
        homeRecents = try c.decodeIfPresent(Bool.self, forKey: .homeRecents) ?? d.homeRecents
        homePinned = try c.decodeIfPresent(Bool.self, forKey: .homePinned) ?? d.homePinned
        homeStats = try c.decodeIfPresent(Bool.self, forKey: .homeStats) ?? d.homeStats
        // Unknown section names from a newer build are dropped instead of failing the whole decode.
        let rawOrder = try c.decodeIfPresent([String].self, forKey: .homeOrder)
        homeOrder = rawOrder.map { $0.compactMap(HomeSection.init(rawValue:)) } ?? d.homeOrder
        recordListening = try c.decodeIfPresent(Bool.self, forKey: .recordListening) ?? d.recordListening
        lyricsAwake = try c.decodeIfPresent(Bool.self, forKey: .lyricsAwake) ?? d.lyricsAwake
        tabHaptics = try c.decodeIfPresent(Bool.self, forKey: .tabHaptics) ?? d.tabHaptics
    }
}

extension Notification.Name {
    static let eeveeExtrasChanged = Notification.Name("EeveeExtrasChanged")
}

extension UserDefaults {
    @UserDefault(key: "eeveePremiumExtrasOptions", defaultValue: ExtrasOptions())
    static var extrasOptions
}
