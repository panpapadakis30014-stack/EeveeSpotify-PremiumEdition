import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

// Actual phone diagnostics: online y769/h83; offline y751/h49, window h852, safe34.
let onlineInset = GlassTabBarGeometry.bottomInset(stockBottom: 852, windowBottom: 852, homeInset: 34)
let offlineInset = GlassTabBarGeometry.bottomInset(stockBottom: 800, windowBottom: 852, homeInset: 34)
check(onlineInset == 34, "online keeps the home indicator inset")
check(offlineInset == 0, "offline must leave all 49 points available for icons")
let online = CGRect(x: 0, y: 0, width: 393, height: 83)
let offline = CGRect(x: 0, y: 0, width: 393, height: 49)
check(GlassTabBarGeometry.phoneFrame(in: online, bottomInset: onlineInset) == online, "online fits its container")
check(GlassTabBarGeometry.phoneFrame(in: offline, bottomInset: offlineInset) == offline, "offline stays above the banner")
for bottom in stride(from: 800.0, through: 852.0, by: 1) {
    let inset = GlassTabBarGeometry.bottomInset(stockBottom: bottom, windowBottom: 852, homeInset: 34)
    let frame = GlassTabBarGeometry.phoneFrame(in: CGRect(x: 0, y: 0, width: 393, height: 49 + inset), bottomInset: inset)
    check(frame.minY == 0 && frame.maxY == 49 + inset, "transition never extends into offline strip")
    check(frame.height - inset == 49, "transition retains full icon height")
}
check(GlassTabBarGeometry.bottomInset(stockBottom: 667, windowBottom: 667, homeInset: 0) == 0,
      "phones without home indicator need no extra inset")
check(SpotifyShortcutRoutes.candidates(for: "spotify:internal:now-playing-queue").first == "spotify:now-playing:queue",
      "queue uses the registered route")
check(SpotifyShortcutRoutes.candidates(for: "spotify:recently-played").first == "spotify:internal:recents",
      "recents uses the in-app route")
for uri in ["spotify:collection:tracks", "spotify:collection:downloads", "spotify:internal:sleepTimer", "spotify:internal:equalizer"] {
    check(SpotifyShortcutRoutes.candidates(for: uri) == [uri], "other destinations are preserved")
}
print("POLISH2 device regression checks passed")
