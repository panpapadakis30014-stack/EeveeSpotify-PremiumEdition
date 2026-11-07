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

    // Sleep timer: fade out before Spotify's own timer pauses playback.
    var sleepFade = true
    var sleepFadeSeconds = 60

    // Music-only mode for Home.
    var hidePodcasts = false

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
    }
}

extension Notification.Name {
    static let eeveeExtrasChanged = Notification.Name("EeveeExtrasChanged")
}

extension UserDefaults {
    @UserDefault(key: "eeveePremiumExtrasOptions", defaultValue: ExtrasOptions())
    static var extrasOptions
}
