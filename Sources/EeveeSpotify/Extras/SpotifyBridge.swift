import EeveeSpotifyC
import Foundation
import MediaPlayer
import Network
import ObjectiveC.runtime
import Orion
import UIKit

// Read-only access to Spotify's player plus in-app navigation, shared by Eevee Home
// and the sleep fade. Everything goes through Spotify's own public-in-process APIs
// (the same stateful player the lyrics use, the same link dispatcher Custom Tabs use);
// nothing here talks to Spotify's servers.

// MARK: - Typed ObjC calls

// Spotify's Swift classes change return types between builds (seconds as Double vs
// milliseconds as Int64), so every call checks the method's encoded return type first.
enum ObjCCall {
    static func returnType(_ object: NSObject, _ selector: Selector) -> Character? {
        guard let method = class_getInstanceMethod(type(of: object), selector) else { return nil }
        let raw = method_copyReturnType(method)
        defer { free(raw) }
        // Skip type qualifiers (r = const, etc.).
        return String(cString: raw).first { !"rnNoORV".contains($0) }
    }

    static func object(_ object: NSObject?, _ name: String) -> NSObject? {
        guard let object else { return nil }
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), returnType(object, selector) == "@" else { return nil }
        return object.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    static func number(_ object: NSObject?, _ name: String) -> Double? {
        guard let object else { return nil }
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), let kind = returnType(object, selector) else { return nil }
        let imp = object.method(for: selector)
        switch kind {
        case "d":
            return unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector) -> Double).self)(object, selector)
        case "f":
            return Double(unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector) -> Float).self)(object, selector))
        case "q", "l", "Q", "L":
            return Double(unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector) -> Int64).self)(object, selector))
        case "i", "I":
            return Double(unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector) -> Int32).self)(object, selector))
        case "B", "c", "C":
            return unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector) -> Bool).self)(object, selector) ? 1 : 0
        case "@":
            let value = object.perform(selector)?.takeUnretainedValue()
            if let number = value as? NSNumber { return number.doubleValue }
            if let date = value as? Date { return date.timeIntervalSince1970 * 1000 }
            if let string = value as? String { return Double(string) }
            return nil
        default:
            return nil
        }
    }

    static func string(_ object: NSObject?, _ name: String) -> String? {
        guard let value = Self.object(object, name) else { return nil }
        if let string = value as? String { return string }
        if let url = value as? URL { return url.absoluteString }
        if value.responds(to: NSSelectorFromString("absoluteString")) {
            return Self.object(value, "absoluteString") as? String
        }
        return value.description
    }

    // Calls a no-argument, void method. Returns false if it isn't there.
    @discardableResult
    static func call(_ object: NSObject?, _ name: String) -> Bool {
        guard let object else { return false }
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector), returnType(object, selector) == "v",
              let method = class_getInstanceMethod(type(of: object), selector),
              method_getNumberOfArguments(method) == 2 else { return false }
        unsafeBitCast(object.method(for: selector), to: (@convention(c) (NSObject, Selector) -> Void).self)(object, selector)
        return true
    }
}

// MARK: - Navigation

struct SpotifyNavigatorGroup: HookGroup { }

enum SpotifyNavigator {
    fileprivate static weak var dispatcher: NSObject?
    private static let navigate = NSSelectorFromString("navigateToURI:options:interactionID:")
    private static var launchActions: [() -> Void] = []
    private(set) static var mainUILoaded = false

    // Runs once Spotify's main UI (tab bar, Home) is up, or right away if it already is.
    static func whenMainUILoaded(_ action: @escaping () -> Void) {
        if mainUILoaded { action() } else { launchActions.append(action) }
    }

    fileprivate static func mainUIDidLoad() {
        guard !mainUILoaded else { return }
        mainUILoaded = true
        let actions = launchActions
        launchActions = []
        actions.forEach { $0() }
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
        guard let url = URL(string: uri) else { return }
        if let dispatcher, dispatcher.responds(to: navigate) {
            typealias Navigate = @convention(c) (NSObject, Selector, NSURL, Int64, AnyObject?) -> Void
            unsafeBitCast(dispatcher.method(for: navigate), to: Navigate.self)(dispatcher, navigate, url as NSURL, 0, nil)
            return
        }
        // Spotify handles its own URL scheme too.
        UIApplication.shared.open(url)
    }
}

class SpotifyNavigatorHook: ClassHook<NSObject> {
    typealias Group = SpotifyNavigatorGroup
    static let targetName = "SPTLinkDispatcherImplementation"

    func setMainUILoaded(_ loaded: Bool) {
        orig.setMainUILoaded(loaded)
        SpotifyNavigator.dispatcher = target
        if loaded { SpotifyNavigator.mainUIDidLoad() }
    }
}

func activateSpotifyNavigator() {
    guard let cls = NSClassFromString(SpotifyNavigatorHook.targetName),
          class_getInstanceMethod(cls, Selector(("setMainUILoaded:"))) != nil else {
        writeDebugLog("[Navigator] link dispatcher missing, falling back to openURL")
        return
    }
    SpotifyNavigatorGroup().activate()
}

// MARK: - Playback

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var artworkURL: URL?
    var contextURI: String?
    var contextTitle: String?
    var isPaused: Bool
    var isSpokenWord: Bool
    var trackURI: String?
    var artistURI: String?
    var albumURI: String?
    var albumTitle: String?
}

// Whether the phone has a usable network path. Spotify's own offline state isn't exposed,
// so Eevee Home treats "no network" as offline.
enum Connectivity {
    private(set) static var isOffline = false
    private static let monitor: NWPathMonitor = {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let offline = path.status != .satisfied
            DispatchQueue.main.async {
                guard offline != isOffline else { return }
                isOffline = offline
                PremiumDiag.note("connectivity: \(offline ? "offline" : "online")")
                NotificationCenter.default.post(name: .eeveeConnectivityChanged, object: nil)
            }
        }
        monitor.start(queue: DispatchQueue(label: "eevee.connectivity"))
        return monitor
    }()

    static func start() { _ = monitor }
}

extension Notification.Name {
    static let eeveeConnectivityChanged = Notification.Name("EeveeConnectivityChanged")
}

enum SleepTimerState: Equatable {
    case off
    case at(Date)
    case endOfTrack
}

enum SpotifyPlayback {
    private static var loggedState = false
    private static var loggedMeta = false

    // Tracks waiting in the queue after the current one, if Spotify tells us.
    static var upNextCount: Int? {
        ObjCCall.number(player, "numberOfNextTracks").map { Int($0) }
    }

    static var player: NSObject? { statefulPlayer.map { $0 as AnyObject } as? NSObject }
    static var state: NSObject? { ObjCCall.object(player, "playerState") }

    static var isPaused: Bool {
        if let paused = ObjCCall.number(player, "isPaused") { return paused != 0 }
        if let paused = ObjCCall.number(state, "isPaused") { return paused != 0 }
        return (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double ?? 0) == 0
    }

    static var hasPlayer: Bool { player != nil }

    static func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    static func pause() {
        if ObjCCall.call(player, "pause") { return }
        tapButton(["SPTNowPlayingPlayButton", "NowPlayingBar.PlayPauseButton"])
    }

    static func resume() {
        if ObjCCall.call(player, "resume") { return }
        tapButton(["SPTNowPlayingPlayButton", "NowPlayingBar.PlayPauseButton"])
    }

    static func next() {
        if ObjCCall.call(player, "skipToNextTrack") { return }
        tapButton(["SPTNowPlayingNextTrackButton"])
    }

    static func previous() {
        if ObjCCall.call(player, "skipToPreviousTrack") { return }
        tapButton(["SPTNowPlayingPreviousTrackButton"])
    }

    private static func tapButton(_ ids: [String]) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            if let button = window.eeveeFirst(UIView.self, where: { view in ids.contains { view.accessibilityIdentifier?.contains($0) == true } }),
               EeveeFireTap(button) { return }
        }
        writeDebugLog("[Playback] no player and no button for \(ids)")
    }

    // Seconds into / length of the current track. Spotify reports either seconds or ms
    // depending on build, so the lock-screen duration (always seconds) settles the unit.
    static var timing: (position: Double, duration: Double)? {
        guard var position = ObjCCall.number(player, "position"),
              var duration = ObjCCall.number(player, "duration"), duration > 0 else {
            return lockScreenTiming
        }
        let reference = lockScreenTiming?.duration
        let inMilliseconds = reference.map { abs(duration / 1000 - $0) < abs(duration - $0) } ?? (duration > 20000)
        if inMilliseconds { position /= 1000; duration /= 1000 }
        return (position, duration)
    }

    private static var lockScreenTiming: (position: Double, duration: Double)? {
        guard let info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
              let duration = info[MPMediaItemPropertyPlaybackDuration] as? Double, duration > 0 else { return nil }
        return (info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0, duration)
    }

    static var info: NowPlayingInfo? {
        let track = ObjCCall.object(player, "currentTrack") ?? ObjCCall.object(state, "track")
        let lock = MPNowPlayingInfoCenter.default().nowPlayingInfo
        let title = ObjCCall.string(track, "trackTitle") ?? lock?[MPMediaItemPropertyTitle] as? String
        guard let title, !title.isEmpty else { return nil }
        let artist = ObjCCall.string(track, "artistName") ?? lock?[MPMediaItemPropertyArtist] as? String ?? ""

        var artwork: URL?
        for key in ["spt_coverArtURLLarge", "spt_coverArtURL", "imageURL"] {
            if let raw = ObjCCall.string(track, key), let url = imageURL(raw) { artwork = url; break }
        }
        let context = ObjCCall.string(state, "contextURI")
        let metadata = ObjCCall.object(state, "contextMetadata") as? [String: Any]
        let contextTitle = (metadata?["context_description"] as? String) ?? (metadata?["context_title"] as? String)
        let spoken = ObjCCall.number(track, "isPodcast") == 1 || ObjCCall.number(track, "isAudiobook") == 1
        let meta = ObjCCall.object(track, "metadata") as? [String: Any]
        func metaURI(_ key: String) -> String? {
            guard let value = meta?[key] as? String, value.hasPrefix("spotify:") else { return nil }
            return value
        }
        let trackURI = ObjCCall.string(track, "URI").flatMap { $0.hasPrefix("spotify:") ? $0 : nil }

        if !loggedState {
            loggedState = true
            PremiumDiag.note("playback: player=\(player.map { NSStringFromClass(type(of: $0)) } ?? "nil") state=\(state.map { NSStringFromClass(type(of: $0)) } ?? "nil") track=\(track.map { NSStringFromClass(type(of: $0)) } ?? "nil") context=\(context ?? "nil") art=\(artwork?.absoluteString ?? "nil")")
        }
        if !loggedMeta, let meta {
            loggedMeta = true
            PremiumDiag.note("track meta keys: " + meta.keys.sorted().prefix(40).joined(separator: " ") + " uri=\(trackURI ?? "nil")")
        }
        return NowPlayingInfo(title: title, artist: artist, artworkURL: artwork, contextURI: context,
                              contextTitle: contextTitle, isPaused: isPaused, isSpokenWord: spoken,
                              trackURI: trackURI, artistURI: metaURI("artist_uri"), albumURI: metaURI("album_uri"),
                              albumTitle: meta?["album_title"] as? String)
    }

    // spotify:image:<id> → https://i.scdn.co/image/<id>
    static func imageURL(_ raw: String) -> URL? {
        if raw.hasPrefix("spotify:image:") { return URL(string: "https://i.scdn.co/image/" + raw.dropFirst("spotify:image:".count)) }
        if raw.hasPrefix("http") { return URL(string: raw) }
        return nil
    }

    static var lockScreenArtwork: UIImage? {
        (MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)?
            .image(at: CGSize(width: 300, height: 300))
    }

    // MARK: Sleep timer (Spotify's own, read-only)

    private static var loggedTimer = 0

    static var sleepTimer: SleepTimerState {
        guard let timer = ObjCCall.object(state, "sleepTimer") else { return .off }
        let rawType = ObjCCall.string(timer, "type") ?? ObjCCall.number(timer, "type").map { String(Int($0)) } ?? "?"
        let stamp = ObjCCall.number(timer, "timestamp") ?? 0
        if loggedTimer < 4 {
            loggedTimer += 1
            PremiumDiag.note("sleep timer: class=\(NSStringFromClass(type(of: timer))) type=\(rawType) timestamp=\(stamp)")
        }
        let now = Date().timeIntervalSince1970
        for scale in [1000.0, 1.0] where stamp > 0 {
            let seconds = stamp / scale
            if seconds > now - 60, seconds < now + 86_400 * 2 { return .at(Date(timeIntervalSince1970: seconds)) }
        }
        let lowered = rawType.lowercased()
        if lowered.contains("end") || lowered.contains("track") || lowered == "2" { return .endOfTrack }
        return .off
    }
}
