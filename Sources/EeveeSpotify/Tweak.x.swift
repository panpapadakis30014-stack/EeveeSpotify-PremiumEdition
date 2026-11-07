import Orion
import EeveeSpotifyC
import UIKit
import Foundation
import ObjectiveC.runtime

func writeDebugLog(_ message: String) {
    EeveeLog.write("[EeveeSpotify] " + message)
}

// Kept in the environment so Orion reinits in the same process don't restart the 30s auth window.
let tweakInitTime: Date = {
    if let existing = getenv("EEVEE_BOOT_TIME"),
       let interval = Double(String(cString: existing)) {
        return Date(timeIntervalSince1970: interval)
    }
    let now = Date()
    setenv("EEVEE_BOOT_TIME", "\(now.timeIntervalSince1970)", 1)
    return now
}()

func exitApplication() {
    UIControl().sendAction(#selector(URLSessionTask.suspend), to: UIApplication.shared, for: nil)
    Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
        exit(EXIT_SUCCESS)
    }
}

// Read-only network hooks: observe the bootstrap account type for PremiumGate,
// and (for verified Premium accounts) serve custom lyrics / strip promo slots.
struct NetworkHooksGroup: HookGroup { }

// Capture the now-playing stateful player for lyrics + karaoke.
struct LegacyStatefulPlayerGroup: HookGroup { }
struct StatefulPlayerGroup: HookGroup { }

func activateStatefulPlayerCapture() {
    guard let cls = NSClassFromString("NowPlaying_PlatformImpl.NowPlayingPlatformSwiftServiceImplementation") else {
        writeDebugLog("[INIT] Skipped stateful player capture (service class missing)")
        return
    }
    if EeveeSpotify.hookTarget == .lastAvailableiOS14 {
        if class_getInstanceMethod(cls, Selector(("provideStatefulPlayer"))) != nil {
            LegacyStatefulPlayerGroup().activate()
        }
    } else if class_getInstanceMethod(cls, Selector(("provideStatefulPlayerWithFeatureIdentifier:"))) != nil {
        StatefulPlayerGroup().activate()
    } else {
        writeDebugLog("[INIT] Skipped stateful player capture (selector missing)")
    }
}

func activateNetworkHooks() {
    guard NSClassFromString(SPTDataLoaderServiceHook.targetName) != nil else {
        writeDebugLog("[INIT] Skipped NetworkHooksGroup (SPTDataLoaderService missing)")
        return
    }
    NetworkHooksGroup().activate()
}

// MARK: - Bootstrap breadcrumbs
@inline(__always)
func eeveeBreadcrumb(_ label: String) {
    let path = NSTemporaryDirectory() + "eeveespotify_boot.txt"
    let ts = Date().description
    let line = "[\(ts)] \(label)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: path), let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

@inline(__always)
func eeveeEnvFlag(_ name: String) -> Bool {
    guard let v = getenv(name) else { return false }
    let s = String(cString: v).lowercased()
    return s == "1" || s == "true" || s == "yes" || s == "y"
}

struct EeveeSpotify: Tweak {
    static let version = "7.0.0"
    static let buildNumber = "1"
    static let spotifyVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    static let repoSlug = GeneratedConfig.repoSlug
    
    static var hookTarget: VersionHookTarget {
        let version = spotifyVersion
        
        eeveeLog("[EeveeSpotify] Detected Spotify version: \(version)")
        
        switch version {
        case "9.0.48":
            return .lastAvailableiOS15
        case "8.9.8":
            return .lastAvailableiOS14
        case _ where version.contains("9.1"):
            return .v91
        default:
            return .latest
        }
    }
    
    // MARK: - Non-fatal hook error handling
    // Orion's default fatalErrors on any failed hook, including DefaultGroup hooks activated before init().
    static func handleError(_ error: OrionHookError) {
        let description = error.description
        eeveeLog("[EeveeSpotify][OrionError] Hook activation failed (non-fatal): %@", description)
        writeDebugLog("[ORION ERROR] \(description)")
        eeveeBreadcrumb("Orion hook activation failed (continuing): \(description)")
    }

    init() {
        eeveeBreadcrumb("Tweak init() entered")

        if eeveeEnvFlag("EEVEE_DISABLE_ALL") {
            eeveeBreadcrumb("EEVEE_DISABLE_ALL=1 -> returning without hooks")
            return
        }

        let spotifyBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        writeDebugLog("=== EeveeSpotify Premium Edition \(EeveeSpotify.version) (build \(EeveeSpotify.buildNumber)) starting ===")
        writeDebugLog("[INIT] Spotify: \(EeveeSpotify.spotifyVersion) (build \(spotifyBuild))")
        writeDebugLog("[INIT] iOS: \(UIDevice.current.systemVersion), Device: \(UIDevice.current.model)")
        writeDebugLog("[INIT] Hook target: \(EeveeSpotify.hookTarget)")
        writeDebugLog("[INIT] Lyrics source: \(UserDefaults.lyricsSource)")

        // Always on, read-only: lets PremiumGate see the real account type that
        // Spotify's servers report. Nothing is modified for non-Premium accounts.
        activateNetworkHooks()
        activatePremiumObserver()

        let premiumStatus = PremiumGate.statusAtLaunch
        PremiumDiag.note("launch: Spotify \(EeveeSpotify.spotifyVersion), premium status at launch = \(premiumStatus)")
        _ = tweakInitTime
        writeDebugLog("[INIT] Premium status at launch: \(premiumStatus)")

        guard premiumStatus == .premium else {
            // Unknown (first launch / after a reset) or a free account: run stock
            // Spotify. PremiumGate prompts for a restart once Premium is verified.
            writeDebugLog("[INIT] Features disabled until an active Spotify Premium subscription is verified")
            return
        }

        activateTelemetryBlock()
        activateTheme()
        activateLiquidGlass()
        activatePlayerGestures()
        activatePlayerHaptics()
        activateHomeDeclutter()
        activateGlassCustomTabs()
        activateHomeGradient()
        activateArtistHides()
        activatePlaylistHides()
        HideJam.activate()
        activateRemoteFlags()
        activateRatingPromptBlock()

        activateEeveeCrossfadeForce()
        activateEeveeAdBlockerExtended()
        activateUpsellPopupBlocker()
        activateUpsellServiceBlocker()
        activateClientMessagingPlatformBlocker()

        if NSClassFromString("HUBViewModelBuilderImplementation") != nil {
            AdBlockerGroup().activate()
            eeveeLog("[EeveeSpotify] AdBlockerGroup activated")
        }

        // UIPasteboard.general is a private subclass whose setters bypass the base-class hooks.
        PasteboardConcreteSwizzler.install()

        activateCarPlayCrashFix()
        activateStatefulPlayerCapture()
        activateStartupPage()
        activateSpotifyNavigator()
        activateEeveeHome()
        SleepFade.activate()
        QualityOfLife.activate()

        if EeveeSpotify.hookTarget == .v91 {
            if UserDefaults.lyricsSource.isReplacingLyrics {
                let fullscreenOK: Bool = {
                    if let cls = NSClassFromString("Lyrics_FullscreenElementPageImpl.FullscreenElementViewController") {
                        return class_getInstanceMethod(cls, #selector(UIViewController.viewDidLoad)) != nil
                    }
                    return false
                }()

                let npvOK: Bool = {
                    if let cls = NSClassFromString("NowPlaying_ScrollImpl.NPVScrollViewController") {
                        return class_getInstanceMethod(cls, #selector(UIViewController.viewWillAppear(_:))) != nil
                            && class_getInstanceMethod(cls, #selector(UIViewController.viewWillDisappear(_:))) != nil
                    }
                    return false
                }()

                if fullscreenOK {
                    BaseLyricsGroup().activate()
                } else {
                    writeDebugLog("[INIT] Skipped BaseLyricsGroup (fullscreen VC missing)")
                }

                if npvOK {
                    V91LyricsGroup().activate()
                } else {
                    writeDebugLog("[INIT] Skipped V91LyricsGroup (NPVScrollViewController missing)")
                }
            }

            if let cls = NSClassFromString("ProfileSettingsSection"),
               class_getInstanceMethod(cls, Selector(("numberOfRows"))) != nil,
               class_getInstanceMethod(cls, Selector(("didSelectRow:"))) != nil,
               class_getInstanceMethod(cls, Selector(("cellForRow:"))) != nil {

                UniversalSettingsIntegrationProfileGroup().activate()

                if NSClassFromString("SettingsViewController") != nil {
                    UniversalSettingsIntegrationSettingsVCGroup().activate()
                }
                // Removed in 9.1.36.
                if NSClassFromString("RootSettingsViewController") != nil {
                    UniversalSettingsIntegrationRootSettingsVCGroup().activate()
                }
                UniversalSettingsIntegrationNavGroup().activate()

            } else {
                writeDebugLog("[INIT] Skipped settings integration (ProfileSettingsSection API mismatch)")
            }

            // 9.1.44+: SettingsListViewController replaced ProfileSettingsSection.
            if NSClassFromString("_TtC21Settings_PlatformImpl26SettingsListViewController") != nil {
                UniversalSettingsIntegrationListVCGroup().activate()
                writeDebugLog("[INIT] Activated SettingsListViewController hook (9.1.44 path)")
            } else {
                writeDebugLog("[INIT] Settings_PlatformImpl.SettingsListViewController missing")
            }
            eeveeLog("[EeveeSpotify] Initialization complete for 9.1.x")
            TrueShuffleHook.install()
            activateSponsorBlock()
            activateKaraokeHooks()
            return
        }

        if UserDefaults.experimentsOptions.showInstagramDestination {
            InstgramDestinationGroup().activate()
        }

        if UserDefaults.darkPopUps {
            DarkPopUps().activate()
        }

        if UserDefaults.lyricsSource.isReplacingLyrics {
            BaseLyricsGroup().activate()
            LyricsErrorHandlingGroup().activate()

            if EeveeSpotify.hookTarget == .latest {
                ModernLyricsGroup().activate()
            }
            else {
                LegacyLyricsGroup().activate()
            }
        }

        UniversalSettingsIntegrationProfileGroup().activate()
        UniversalSettingsIntegrationSettingsVCGroup().activate()
        if NSClassFromString("RootSettingsViewController") != nil {
            UniversalSettingsIntegrationRootSettingsVCGroup().activate()
        }
        if NSClassFromString("_TtC21Settings_PlatformImpl26SettingsListViewController") != nil {
            UniversalSettingsIntegrationListVCGroup().activate()
        }
        UniversalSettingsIntegrationNavGroup().activate()
        SettingsIntegrationGroup().activate()

        TrueShuffleHook.install()
        activateSponsorBlock()
        activateKaraokeHooks()
    }
}
