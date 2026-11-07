import UIKit

// An on-device listening log: which playlists/albums/artists were played (for "Jump back in")
// and how long music played each day (for "Your listening"). It only polls Spotify's local
// player every few seconds; nothing is sent anywhere and it can be wiped from Settings.

struct RecentContext: Codable, Equatable {
    var uri: String
    var title: String
    var kind: String
    var artwork: String?
    var lastPlayed: Date
}

struct ListeningDay: Codable, Equatable {
    var seconds: Double = 0
    var artists: [String: Double] = [:]
}

struct ListeningSummary: Equatable {
    var today: Double
    var week: Double
    var topArtist: String?
    var activeDays: Int
}

extension Notification.Name {
    static let eeveeListeningChanged = Notification.Name("EeveeListeningChanged")
}

enum ListeningLog {
    private static let recentsKey = "eeveeRecentContexts"
    private static let daysKey = "eeveeListeningDays"
    private static let interval: TimeInterval = 5
    private static let keepRecents = 24
    private static let keepDays = 35

    private(set) static var recents: [RecentContext] = load(recentsKey) ?? []
    private static var days: [String: ListeningDay] = load(daysKey) ?? [:]
    private static var timer: Timer?
    private static var lastTick: Date?
    private static var unsaved: TimeInterval = 0
    private static var lastContext: String?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func start() {
        guard timer == nil else { return }
        let tick = Timer(timeInterval: interval, repeats: true) { _ in step() }
        tick.tolerance = 1
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in saveDays() }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in saveDays() }
        PremiumDiag.note("listening log on: \(recents.count) recents, \(days.count) days")
    }

    // MARK: Polling

    private static func step() {
        guard UserDefaults.extrasOptionsCached.recordListening else {
            lastTick = nil
            return
        }
        let now = Date()
        defer { lastTick = now }
        guard let info = SpotifyPlayback.info else { return }

        if let uri = info.contextURI, worthKeeping(uri), uri != lastContext || recents.first?.uri != uri {
            lastContext = uri
            remember(uri, info: info, at: now)
        }

        guard !info.isPaused, let last = lastTick else { return }
        // A long gap means the app was suspended; only count the polling interval.
        let elapsed = min(now.timeIntervalSince(last), interval * 2)
        guard elapsed > 0 else { return }
        let key = dayFormatter.string(from: now)
        var day = days[key] ?? ListeningDay()
        day.seconds += elapsed
        let artist = info.artist.trimmingCharacters(in: .whitespaces)
        if !artist.isEmpty {
            // Featured artists are listed after a comma; credit the main one.
            let main = artist.components(separatedBy: ", ").first ?? artist
            day.artists[main, default: 0] += elapsed
        }
        days[key] = day
        unsaved += elapsed
        if unsaved >= 60 {
            saveDays()
            NotificationCenter.default.post(name: .eeveeListeningChanged, object: nil)
        }
    }

    private static func worthKeeping(_ uri: String) -> Bool {
        guard uri.hasPrefix("spotify:") else { return false }
        let skipped = [":internal:", "spotify:search", "spotify:now-playing", ":queue", "spotify:app:"]
        return !skipped.contains { uri.contains($0) }
    }

    private static func contextKind(of uri: String) -> String {
        if uri.contains(":collection:tracks") || uri.hasSuffix(":collection") { return "Liked Songs" }
        if uri.contains(":collection:your-episodes") { return "Your Episodes" }
        if uri.contains(":album:") { return "Album" }
        if uri.contains(":artist:") { return "Artist" }
        if uri.contains(":show:") { return "Podcast" }
        if uri.contains(":episode:") { return "Episode" }
        if uri.contains(":station:") || uri.contains(":radio:") { return "Radio" }
        return "Playlist"
    }

    private static func remember(_ uri: String, info: NowPlayingInfo, at date: Date) {
        let kind = contextKind(of: uri)
        let title: String
        switch kind {
        case "Liked Songs", "Your Episodes": title = kind
        case "Album": title = info.contextTitle ?? info.albumTitle ?? info.title
        case "Artist": title = info.contextTitle ?? info.artist
        default: title = info.contextTitle ?? info.title
        }
        var entry = recents.first { $0.uri == uri } ?? RecentContext(uri: uri, title: title, kind: kind, artwork: nil, lastPlayed: date)
        entry.lastPlayed = date
        if entry.title.isEmpty || entry.title == info.title { entry.title = title }
        // The first cover seen stays, so the card doesn't change on every track.
        if entry.artwork == nil { entry.artwork = info.artworkURL?.absoluteString }
        recents.removeAll { $0.uri == uri }
        recents.insert(entry, at: 0)
        if recents.count > keepRecents { recents.removeLast(recents.count - keepRecents) }
        save(recents, recentsKey)
        NotificationCenter.default.post(name: .eeveeListeningChanged, object: nil)
    }

    // MARK: Editing

    static func remove(_ uri: String) {
        recents.removeAll { $0.uri == uri }
        save(recents, recentsKey)
        NotificationCenter.default.post(name: .eeveeListeningChanged, object: nil)
    }

    static func reset() {
        recents = []
        days = [:]
        lastContext = nil
        unsaved = 0
        UserDefaults.standard.removeObject(forKey: recentsKey)
        UserDefaults.standard.removeObject(forKey: daysKey)
        NotificationCenter.default.post(name: .eeveeListeningChanged, object: nil)
    }

    // MARK: Summary

    static var summary: ListeningSummary {
        let calendar = Calendar.current
        let today = Date()
        var week: Double = 0
        var artists: [String: Double] = [:]
        var active = 0
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
                  let day = days[dayFormatter.string(from: date)] else { continue }
            week += day.seconds
            if day.seconds >= 60 { active += 1 }
            day.artists.forEach { artists[$0.key, default: 0] += $0.value }
        }
        let top = artists.max { $0.value < $1.value }.flatMap { $0.value >= 60 ? $0.key : nil }
        return ListeningSummary(today: days[dayFormatter.string(from: today)]?.seconds ?? 0, week: week,
                                topArtist: top, activeDays: active)
    }

    // MARK: Storage

    private static func saveDays() {
        guard unsaved > 0 else { return }
        unsaved = 0
        // Only the last few weeks are kept.
        if days.count > keepDays {
            let keep = Set(days.keys.sorted().suffix(keepDays))
            days = days.filter { keep.contains($0.key) }
        }
        save(days, daysKey)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, _ key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension UserDefaults {
    // Decoded once and refreshed on change, for code that reads options every few seconds.
    private static var cachedExtras: ExtrasOptions?
    private static let extrasCacheObserver = NotificationCenter.default.addObserver(
        forName: .eeveeExtrasChanged, object: nil, queue: .main
    ) { _ in cachedExtras = nil }

    static var extrasOptionsCached: ExtrasOptions {
        _ = extrasCacheObserver
        if let cached = cachedExtras { return cached }
        let fresh = extrasOptions
        cachedExtras = fresh
        return fresh
    }
}
