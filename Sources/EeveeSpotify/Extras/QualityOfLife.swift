import AVFoundation
import UIKit

// Small client-side conveniences. Each one only reads Spotify's player state or uses
// Spotify's own in-app navigation; none of them touch the account or the network.

enum QualityOfLife {
    static func activate() {
        let options = ExtrasOptions.launch
        Connectivity.start()
        if options.resumeOnLaunch {
            SpotifyNavigator.whenMainUILoaded { ResumeOnLaunch.start(needsHeadphones: options.resumeNeedsHeadphones) }
        }
        if options.offlineOpensDownloads {
            SpotifyNavigator.whenMainUILoaded {
                // Give the network monitor a moment to report after a cold start.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard Connectivity.isOffline else { return }
                    PremiumDiag.note("offline at launch: opening Downloads")
                    SpotifyNavigator.open("spotify:collection:downloads")
                }
            }
        }
        KeepAwake.start()
    }
}

// Picks the last track back up once Spotify has loaded it, optionally only when
// headphones, Bluetooth, AirPlay or a car are connected (so it never blasts the speaker).
private enum ResumeOnLaunch {
    private static var attempts = 0

    static func start(needsHeadphones: Bool) {
        attempts = 0
        step(needsHeadphones)
    }

    private static func step(_ needsHeadphones: Bool) {
        attempts += 1
        guard attempts <= 15 else {
            PremiumDiag.note("resume on launch: no track loaded, gave up")
            return
        }
        guard SpotifyPlayback.info != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { step(needsHeadphones) }
            return
        }
        guard SpotifyPlayback.isPaused else { return }
        if needsHeadphones && !privateOutput {
            PremiumDiag.note("resume on launch: skipped, playing through the speaker")
            return
        }
        SpotifyPlayback.resume()
        PremiumDiag.note("resume on launch: resumed after \(attempts)s")
    }

    private static var privateOutput: Bool {
        let wanted: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP,
                                                .carAudio, .airPlay, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { wanted.contains($0.portType) }
    }
}

// Keeps the screen on while music plays and the phone is charging: a bedside or
// dashboard display. Lets the screen sleep again as soon as either stops.
enum KeepAwake {
    private static var timer: Timer?
    private static var applied = false
    private static let observer = NotificationCenter.default.addObserver(
        forName: .eeveeExtrasChanged, object: nil, queue: .main
    ) { _ in refreshTimer() }

    static func start() {
        _ = observer
        refreshTimer()
    }

    private static func refreshTimer() {
        let enabled = UserDefaults.extrasOptions.awakeWhileCharging
        if enabled, timer == nil {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let tick = Timer(timeInterval: 3, repeats: true) { _ in step() }
            tick.tolerance = 1
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
            step()
        } else if !enabled, let current = timer {
            current.invalidate()
            timer = nil
            set(false)
        }
    }

    private static func step() {
        let charging = [.charging, .full].contains(UIDevice.current.batteryState)
        let playing = SpotifyPlayback.info != nil && !SpotifyPlayback.isPaused
        set(charging && playing && UIApplication.shared.applicationState == .active)
    }

    private static func set(_ awake: Bool) {
        guard awake != applied else { return }
        applied = awake
        UIApplication.shared.isIdleTimerDisabled = awake
        PremiumDiag.note("keep awake \(awake ? "on" : "off")")
    }
}
