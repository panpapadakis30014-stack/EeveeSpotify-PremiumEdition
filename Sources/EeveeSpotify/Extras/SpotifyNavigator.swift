import Foundation
import ObjectiveC.runtime

enum SpotifyNavigator {
    private(set) static weak var dispatcher: NSObject?
    private static let navigate = NSSelectorFromString("navigateToURI:options:interactionID:")
    private static var launchActions: [() -> Void] = []
    private(set) static var mainUILoaded = false

    // The Quasar navigation service does not use the legacy dispatcher's UI-loaded
    // setter. Observe the object returned by the actual navigation service instead.
    static func capture(_ object: NSObject, via source: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { capture(object, via: source) }
            return
        }
        let name = NSStringFromClass(type(of: object))
        guard !name.hasSuffix("NoOpLinkDispatcher"),
              matches(object, NSSelectorFromString("navigateToURI:options:reason:completionHandler:resultHandler:"),
                      returns: "v", arguments: ["@", "q", "@", "@", "@"]) ||
                matches(object, navigate, returns: "v", arguments: ["@", "q", "@"]) else { return }
        guard dispatcher !== object else { return }
        dispatcher = object
        PremiumDiag.note("navigation dispatcher captured via \(source): \(name)")
    }

    // Runs once Spotify's main UI (tab bar, Home) is up, or right away if it already is.
    static func whenMainUILoaded(_ action: @escaping () -> Void) {
        if mainUILoaded { DispatchQueue.main.async(execute: action) } else { launchActions.append(action) }
    }

    static func mainUIDidLoad() {
        guard !mainUILoaded else { return }
        mainUILoaded = true
        let actions = launchActions
        launchActions = []
        // Spotify may report this off the main thread; everything queued here touches UI.
        DispatchQueue.main.async { actions.forEach { $0() } }
    }

    // spotify:track:ID → https://open.spotify.com/track/ID (what the share sheet expects).
    static func webLink(_ uri: String) -> URL? {
        let parts = uri.split(separator: ":").map(String.init)
        guard parts.count >= 3, parts[0] == "spotify" else { return nil }
        let kinds = ["track", "album", "artist", "playlist", "show", "episode", "audiobook"]
        guard let index = parts.firstIndex(where: kinds.contains), index + 1 < parts.count else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[index])/\(parts[index + 1])")
    }

    static func open(_ uri: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { open(uri) }
            return
        }
        let candidates = SpotifyShortcutRoutes.candidates(for: uri)
        guard let dispatcher else {
            PremiumDiag.note("navigation waiting for Spotify UI")
            return
        }
        let check = NSSelectorFromString("canOpenURI:allowExternalApps:")
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if matches(dispatcher, check, returns: "B", arguments: ["@", "B"]) {
                typealias CanOpen = @convention(c) (NSObject, Selector, NSURL, Bool) -> Bool
                guard unsafeBitCast(dispatcher.method(for: check), to: CanOpen.self)(dispatcher, check, url as NSURL, false) else { continue }
            }
            if navigateInApp(url, using: dispatcher) {
                // Record the route family only, never playlist/track IDs.
                PremiumDiag.note("navigation dispatched: \(candidate.split(separator: ":").prefix(2).joined(separator: ":"))")
                return
            }
        }
        PremiumDiag.note("navigation unavailable: \(uri)")
    }

    // 9.1.94 uses the reason/completion/result form. Older builds used interactionID.
    // Check the ABI before calling either; never send internal routes through iOS.
    static func navigateInApp(_ url: URL, using dispatcher: NSObject) -> Bool {
        let current = NSSelectorFromString("navigateToURI:options:reason:completionHandler:resultHandler:")
        if matches(dispatcher, current, returns: "v", arguments: ["@", "q", "@", "@", "@"]) {
            typealias Navigate = @convention(c) (NSObject, Selector, NSURL, Int64, AnyObject?, AnyObject?, AnyObject?) -> Void
            unsafeBitCast(dispatcher.method(for: current), to: Navigate.self)(dispatcher, current, url as NSURL, 0, nil, nil, nil)
            return true
        }
        if matches(dispatcher, navigate, returns: "v", arguments: ["@", "q", "@"]) {
            typealias Navigate = @convention(c) (NSObject, Selector, NSURL, Int64, AnyObject?) -> Void
            unsafeBitCast(dispatcher.method(for: navigate), to: Navigate.self)(dispatcher, navigate, url as NSURL, 0, nil)
            return true
        }
        return false
    }

    private static func matches(_ object: NSObject, _ selector: Selector, returns result: Character,
                                arguments: [Character]) -> Bool {
        guard object.responds(to: selector), let method = class_getInstanceMethod(type(of: object), selector),
              method_getNumberOfArguments(method) == UInt32(arguments.count + 2) else { return false }
        func code(_ raw: UnsafeMutablePointer<CChar>) -> Character? {
            defer { free(raw) }
            return String(cString: raw).first { !"rnNoORV".contains($0) }
        }
        guard code(method_copyReturnType(method)) == result else { return false }
        return arguments.enumerated().allSatisfy { index, expected in
            guard let raw = method_copyArgumentType(method, UInt32(index + 2)) else { return false }
            return code(raw) == expected
        }
    }
}

