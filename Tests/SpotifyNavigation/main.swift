import Foundation

// Compile the production navigator against the Objective-C runtime on macOS.
// These doubles expose the actual selector shapes, without importing Spotify.
enum PremiumDiag {
    static var notes: [String] = []
    static func note(_ text: String) { notes.append(text) }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

class CurrentDispatcher: NSObject {
    var opened: [String] = []
    var checked: [String] = []
    var allowed: Set<String> = ["spotify:collection:tracks", "spotify:collection:downloads",
                                "spotify:internal:recents", "spotify:now-playing:queue",
                                "spotify:internal:sleepTimer", "spotify:internal:equalizer"]

    @objc(canOpenURI:allowExternalApps:)
    dynamic func canOpenURI(_ uri: NSURL, allowExternalApps: Bool) -> Bool {
        check(!allowExternalApps, "shortcuts must stay inside this Spotify installation")
        checked.append(uri.absoluteString ?? "")
        return allowed.contains(uri.absoluteString ?? "")
    }

    @objc(navigateToURI:options:reason:completionHandler:resultHandler:)
    dynamic func navigateToURI(_ uri: NSURL, options: Int64, reason: AnyObject?,
                               completionHandler: AnyObject?, resultHandler: AnyObject?) {
        check(Thread.isMainThread, "navigation must run on the main thread")
        opened.append(uri.absoluteString ?? "")
    }
}

final class LegacyDispatcher: NSObject {
    var opened: [String] = []

    @objc(navigateToURI:options:interactionID:)
    dynamic func navigateToURI(_ uri: NSURL, options: Int64, interactionID: AnyObject?) {
        opened.append(uri.absoluteString ?? "")
    }
}

@objc(EEVEETestNoOpLinkDispatcher)
final class NoOpDispatcher: CurrentDispatcher { }

final class WrongABIDispatcher: NSObject {
    @objc(navigateToURI:options:reason:completionHandler:resultHandler:)
    dynamic func navigateToURI(_ uri: NSURL, options: Int64, reason: AnyObject?,
                               completionHandler: AnyObject?, resultHandler: AnyObject?) -> Int64 {
        fatalError("must not invoke an incompatible ABI")
    }
}

check(Thread.isMainThread, "test must start on main thread")
SpotifyNavigator.open("spotify:collection:tracks")
check(PremiumDiag.notes.last == "navigation waiting for Spotify UI", "missing dispatcher is diagnosed")

// Reproduce the device failure: this provider result never sends setMainUILoaded.
let current = CurrentDispatcher()
SpotifyNavigator.capture(current, via: "Quasar URI service")
check(SpotifyNavigator.dispatcher === current, "provider capture must not depend on the unused legacy UI setter")
for uri in ["spotify:collection:tracks", "spotify:collection:downloads", "spotify:recently-played",
            "spotify:internal:now-playing-queue", "spotify:internal:sleepTimer", "spotify:internal:equalizer"] {
    SpotifyNavigator.open(uri)
}
check(current.opened == ["spotify:collection:tracks", "spotify:collection:downloads", "spotify:internal:recents",
                         "spotify:now-playing:queue", "spotify:internal:sleepTimer", "spotify:internal:equalizer"],
      "every Home shortcut must dispatch after provider capture")

current.allowed = ["spotify:recently-played"]
SpotifyNavigator.open("spotify:recently-played")
check(current.opened.last == "spotify:recently-played", "try the supported fallback when the preferred alias is unavailable")
let before = current.opened.count
SpotifyNavigator.open("spotify:internal:unsupported-test")
check(current.opened.count == before, "unsupported routes must not be dispatched")

let wrong = WrongABIDispatcher()
SpotifyNavigator.capture(wrong, via: "test")
check(SpotifyNavigator.dispatcher === current, "incompatible providers must not replace the working dispatcher")
let noOp = NoOpDispatcher()
SpotifyNavigator.capture(noOp, via: "test")
check(SpotifyNavigator.dispatcher === current, "placeholder providers must not replace the working dispatcher")

let legacy = LegacyDispatcher()
SpotifyNavigator.capture(legacy, via: "legacy")
SpotifyNavigator.open("spotify:collection:tracks")
check(legacy.opened == ["spotify:collection:tracks"], "older dispatcher ABI remains supported")
print("Spotify navigation runtime regression checks passed")
