import Foundation

// EeveeSpotify Premium Edition: the tweak never alters the account's entitlements.
// It reads the subscription type Spotify's own servers report in the bootstrap
// response (read-only: the response is passed through byte-for-byte) and only
// enables EeveeSpotify features for accounts that already have Spotify Premium.

enum PremiumAccountStatus: Int {
    case unknown = 0
    case premium = 1
    case notPremium = 2
}

enum PremiumGate {
    private static let statusKey = "eeveePremiumAccountStatus"
    private static let lock = NSLock()
    private static var shownVerifiedPopUp = false
    private static var shownNotPremiumPopUp = false

    enum Source { case bootstrap, productState }

    // Status at launch time decides which hook groups get activated in init().
    static let statusAtLaunch: PremiumAccountStatus = storedStatus

    private static var storedStatus: PremiumAccountStatus {
        get {
            PremiumAccountStatus(rawValue: UserDefaults.standard.integer(forKey: statusKey)) ?? .unknown
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: statusKey)
        }
    }

    // Live status: network-level features (ad stripping, lyrics) check this so
    // they switch off immediately if Spotify reports the account isn't Premium.
    static var isPremium: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedStatus == .premium
    }

    static var status: PremiumAccountStatus {
        lock.lock(); defer { lock.unlock() }
        return storedStatus
    }

    static func forget() {
        lock.lock(); defer { lock.unlock() }
        storedStatus = .unknown
    }

    // Spotify reports "premium" for every paid plan (Individual, Duo, Family, Student).
    static func record(accountType: String?, catalogue: String?, source: Source = .bootstrap) {
        guard accountType != nil || catalogue != nil else { return }

        let isPremiumAccount = accountType == "premium" || catalogue == "premium"

        // In-app product state can carry placeholder values right after launch,
        // so it may only turn the gate ON early; "not premium" from it counts
        // only once the session has settled. The server bootstrap is authoritative.
        if !isPremiumAccount && source == .productState
            && Date().timeIntervalSince(tweakInitTime) < 30 {
            return
        }

        let newStatus: PremiumAccountStatus = isPremiumAccount ? .premium : .notPremium

        lock.lock()
        let previous = storedStatus
        storedStatus = newStatus
        let showVerified = newStatus == .premium && statusAtLaunch != .premium && !shownVerifiedPopUp
        let showNotPremium = newStatus == .notPremium && !shownNotPremiumPopUp
        if showVerified { shownVerifiedPopUp = true }
        if showNotPremium { shownNotPremiumPopUp = true }
        lock.unlock()

        if previous != newStatus {
            NSLog("[EeveeSpotify][PremiumGate] %@ -> %@ (type=%@ catalogue=%@)",
                  "\(previous)", "\(newStatus)", accountType ?? "nil", catalogue ?? "nil")
        }

        if showVerified {
            PopUpHelper.showPopUp(
                delayed: true,
                message: "Spotify Premium verified. Restart Spotify to enable EeveeSpotify features.",
                buttonText: "Restart",
                secondButtonText: "Later",
                onPrimaryClick: { exitApplication() }
            )
        }
        else if showNotPremium {
            PopUpHelper.showPopUp(
                delayed: true,
                message: statusAtLaunch == .premium
                    ? "Your account no longer has Spotify Premium. EeveeSpotify features are now disabled; Spotify will work normally."
                    : "EeveeSpotify Premium Edition only works with accounts that already have an active Spotify Premium subscription. Its features stay disabled on this account; Spotify will work normally.",
                buttonText: "OK"
            )
        }
    }
}
