import Foundation
import CoreGraphics

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
check(GlassTabBarGeometry.needsCompactRenderer(height: 49, homeInset: 34),
      "offline must use compact glass instead of compressing the system UITabBar")
check(!GlassTabBarGeometry.needsCompactRenderer(height: 83, homeInset: 34),
      "online keeps the system Liquid Glass tab bar")
check(!GlassTabBarGeometry.needsCompactRenderer(height: 49, homeInset: 0),
      "ordinary 49-point bars without a home indicator retain their renderer")
for width: CGFloat in [320, 393, 430, 852] {
    let area = CGRect(x: 0, y: 0, width: width, height: 49)
    for count in 3...6 {
        let frames = GlassTabBarGeometry.compactItemFrames(in: area, count: count)
        check(frames.count == count, "compact bar retains every tab")
        for frame in frames {
            check(area.contains(frame), "compact tab must stay above the offline banner")
            check(frame.height >= 44, "compact tabs retain a usable touch height")
            check(frame.height >= 22 + 2 + 12, "icon and caption fit without squeezing")
        }
        for index in 1..<frames.count {
            check(frames[index - 1].maxX <= frames[index].minX + 0.001, "compact tabs must not overlap")
        }
    }
}
check(GlassTabBarGeometry.compactItemFrames(in: offline, count: 0).isEmpty,
      "loading without tabs must not divide by zero")
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
