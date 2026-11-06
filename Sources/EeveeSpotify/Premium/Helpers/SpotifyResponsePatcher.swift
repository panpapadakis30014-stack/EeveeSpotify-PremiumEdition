import Foundation

// Shared by SPTDataLoaderServiceHook and HttpClientURLSessionHook. Lyrics is
// kept in each caller because its async fetch doesn't fit a sync transform.
//
// Premium Edition: nothing here touches account, entitlement, session, license
// or remote-configuration traffic. The only thing read from the bootstrap
// response is the account type (for PremiumGate); the bytes are passed through
// unmodified. Cosmetic ad/upsell stripping only runs for verified Premium accounts.
enum SpotifyResponsePatcher {

    static func shouldBlock(_ url: URL) -> Bool {
        guard PremiumGate.isPremium else { return false }

        let path = url.path.lowercased()

        // Leftover ad/promo surfaces (Premium accounts don't get ads, but home
        // and upsell feeds still carry promo slots).
        if url.isAdRelated { return true }
        if path.contains("/dac/view/v1/") { return true }
        if path.contains("/esperanto/") && (path.contains("ad") || path.contains("slot")) {
            return true
        }
        return url.isTrialsFacade
            || url.isPremiumMarketing
            || url.isPendragonFetchMessageList
    }

    static func blockedResponseData(for url: URL) -> Data {
        if url.isTrialsFacade {
            return #"{"result":"NOT_ELIGIBLE"}"#.data(using: .utf8)!
        }
        if url.isPremiumMarketing {
            return #"{}"#.data(using: .utf8)!
        }
        return Data()
    }

    static func shouldModify(_ url: URL) -> Bool {
        // Bootstrap is buffered only so PremiumGate can read the account type.
        if url.isBootstrap { return true }

        guard PremiumGate.isPremium else { return false }

        return (BaseLyricsGroup.isActive && url.isLyrics)
            || url.path.lowercased().contains("/dac/view/v1/")
            || BrowsitaSectionStripper.shouldHandle(url)
    }

    enum PatchTag: String {
        case dacEmpty    = "dac"
        case casitaStrip = "casitaStrip"
    }

    struct PatchResult {
        let data: Data
        let tag: PatchTag
    }

    // Returning nil makes the caller replay the original, unmodified bytes.
    static func patch(url: URL, buffer: Data) throws -> PatchResult? {
        if url.isBootstrap {
            PremiumDiag.note("bootstrap seen \(url.path) bytes=\(buffer.count)")
            if let message = try? BootstrapMessage(serializedBytes: buffer) {
                let attributes = message.attributes
                PremiumGate.record(
                    accountType: attributes["type"]?.stringValue,
                    catalogue: attributes["catalogue"]?.stringValue
                )
            }
            return nil
        }

        guard PremiumGate.isPremium else { return nil }

        if url.path.lowercased().contains("/dac/view/v1/") {
            // Empty body = "no ad to render" to the DAC consumer.
            return PatchResult(data: Data(), tag: .dacEmpty)
        }
        if BrowsitaSectionStripper.shouldHandle(url) {
            if let stripped = BrowsitaSectionStripper.strip(buffer, url: url) {
                return PatchResult(data: stripped, tag: .casitaStrip)
            }
            writeDebugLog("[STRIP] no-match \(url.path) size=\(buffer.count)")
            return nil
        }
        return nil
    }
}
