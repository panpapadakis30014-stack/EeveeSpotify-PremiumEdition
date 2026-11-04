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

struct ExtrasOptions: Codable, Equatable {
    var startupPage = StartupPage.home

    init() {}

    // Keep decoding settings saved by older builds when new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startupPage = try c.decodeIfPresent(StartupPage.self, forKey: .startupPage) ?? .home
    }
}

extension UserDefaults {
    @UserDefault(key: "eeveePremiumExtrasOptions", defaultValue: ExtrasOptions())
    static var extrasOptions
}
