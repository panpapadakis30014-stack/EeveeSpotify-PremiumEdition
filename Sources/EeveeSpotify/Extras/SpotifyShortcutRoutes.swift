import Foundation

enum SpotifyShortcutRoutes {
    static func candidates(for uri: String) -> [String] {
        switch uri {
        case "spotify:recently-played", "spotify:internal:recents":
            return ["spotify:internal:recents", "spotify:recently-played"]
        case "spotify:internal:now-playing-queue", "spotify:now-playing:queue":
            return ["spotify:now-playing:queue", "spotify:internal:now-playing-queue"]
        default:
            return [uri]
        }
    }
}
