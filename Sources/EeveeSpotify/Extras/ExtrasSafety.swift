import UIKit

// Crash-loop guard for the Premium Extras (Eevee Home, sleep fade, quality-of-life,
// listening log, the tab bar re-fit). If Spotify dies within the first seconds after
// launch twice in a row, the extras are paused and Spotify runs as it did before them,
// until they are switched back on from Settings → Premium Extras.
//
// Going to the background counts as a clean launch, so swiping the app away is never
// mistaken for a crash.

enum ExtrasSafety {
    private static let armedKey = "eeveeExtrasLaunchArmed"
    private static let exitsKey = "eeveeExtrasEarlyExits"
    private static let pausedKey = "eeveeExtrasPaused"
    private static let stableAfter: TimeInterval = 15
    private static var observer: NSObjectProtocol?

    // Decided once per launch, before any extra is activated.
    private(set) static var safeMode = false

    static func begin() {
        let defaults = UserDefaults.standard
        var exits = defaults.integer(forKey: exitsKey)
        exits = defaults.bool(forKey: armedKey) ? exits + 1 : 0
        defaults.set(exits, forKey: exitsKey)
        if exits >= 2 { defaults.set(true, forKey: pausedKey) }
        safeMode = defaults.bool(forKey: pausedKey)
        if safeMode {
            PremiumDiag.note("extras PAUSED (safe mode) after \(exits) early exits")
            defaults.set(false, forKey: armedKey)
            return
        }

        defaults.set(true, forKey: armedKey)
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in disarm() }
        DispatchQueue.main.asyncAfter(deadline: .now() + stableAfter) { disarm() }
    }

    private static func disarm() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: armedKey) else { return }
        defaults.set(false, forKey: armedKey)
        defaults.set(0, forKey: exitsKey)
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    static var isPaused: Bool { UserDefaults.standard.bool(forKey: pausedKey) }

    // From Settings: turn the extras back on for the next launch.
    static func resume() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: pausedKey)
        defaults.set(0, forKey: exitsKey)
        defaults.set(false, forKey: armedKey)
    }
}
