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
    private static var shownPopUpThisLaunch = false

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
    static func record(accountType: String?, catalogue: String?) {
        guard accountType != nil || catalogue != nil else { return }

        let isPremiumAccount = accountType == "premium" || catalogue == "premium"
        let newStatus: PremiumAccountStatus = isPremiumAccount ? .premium : .notPremium

        lock.lock()
        let previous = storedStatus
        storedStatus = newStatus
        let alreadyShown = shownPopUpThisLaunch
        lock.unlock()

        writeDebugLog("[PREMIUM GATE] type=\(accountType ?? "nil") catalogue=\(catalogue ?? "nil") -> \(newStatus) (was \(previous))")

        guard !alreadyShown else { return }

        if newStatus == .premium && statusAtLaunch != .premium {
            markShown()
            PopUpHelper.showPopUp(
                delayed: true,
                message: "Spotify Premium verified. Restart Spotify to enable EeveeSpotify features.",
                buttonText: "Restart",
                secondButtonText: "Later",
                onPrimaryClick: { exitApplication() }
            )
        }
        else if newStatus == .notPremium {
            markShown()
            PopUpHelper.showPopUp(
                delayed: true,
                message: statusAtLaunch == .premium
                    ? "Your account no longer has Spotify Premium. EeveeSpotify features are now disabled; Spotify will work normally."
                    : "EeveeSpotify Premium Edition only works with accounts that already have an active Spotify Premium subscription. Its features stay disabled on this account; Spotify will work normally.",
                buttonText: "OK"
            )
        }
    }

    private static func markShown() {
        lock.lock(); shownPopUpThisLaunch = true; lock.unlock()
    }
}
