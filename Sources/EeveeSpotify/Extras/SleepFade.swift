import AVFoundation
import MediaPlayer
import UIKit

// Fades the volume out before Spotify's own sleep timer pauses playback, then puts it
// back once playback has stopped. Spotify's timer still does the pausing; this only
// watches it (read-only) and rides the system volume down, like a bedside radio.
//
// "End of track" timers fade over the track's last few seconds instead of a minute.

enum SleepFade {
    private static var timer: Timer?
    private static var startVolume: Float?
    private static var lastTimer = SleepTimerState.off
    private static let restoreKey = "eeveeSleepFadeRestoreVolume"
    private static let endOfTrackWindow = 12.0

    private static let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 10, height: 10))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        return view
    }()

    static func activate() {
        guard UserDefaults.extrasOptions.sleepFade else { return }
        // If Spotify was killed mid-fade, give the volume back on the next launch.
        if let saved = UserDefaults.standard.object(forKey: restoreKey) as? Float {
            UserDefaults.standard.removeObject(forKey: restoreKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { setVolume(saved) }
        }
        DispatchQueue.main.async {
            let tick = Timer(timeInterval: 1, repeats: true) { _ in step() }
            tick.tolerance = 0.2
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
        }
        PremiumDiag.note("sleep fade armed (\(UserDefaults.extrasOptions.sleepFadeSeconds)s)")
    }

    // Seconds until Spotify pauses, and the window to fade over.
    private static func countdown(_ state: SleepTimerState) -> (left: Double, window: Double)? {
        switch state {
        case .off:
            return nil
        case .at(let date):
            return (date.timeIntervalSinceNow, Double(UserDefaults.extrasOptions.sleepFadeSeconds))
        case .endOfTrack:
            guard let timing = SpotifyPlayback.timing else { return nil }
            return (timing.duration - timing.position, endOfTrackWindow)
        }
    }

    private static func step() {
        guard SpotifyPlayback.hasPlayer || startVolume != nil else { return }
        let state = SpotifyPlayback.sleepTimer
        if state != lastTimer {
            PremiumDiag.note("sleep timer now \(state)")
            lastTimer = state
        }
        let paused = SpotifyPlayback.isPaused

        guard let remaining = countdown(state), !paused || startVolume == nil else {
            // Timer cancelled, or Spotify has paused: hand the volume back.
            if let volume = startVolume {
                startVolume = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + (paused ? 1.5 : 0)) { restore(volume) }
            }
            return
        }
        let (left, window) = remaining
        guard !paused, left <= window, left > -5 else {
            if let volume = startVolume, left > window {
                // Timer was extended past the fade window.
                startVolume = nil
                restore(volume)
            }
            return
        }

        if startVolume == nil {
            let current = AVAudioSession.sharedInstance().outputVolume
            guard current > 0.01 else { return }
            startVolume = current
            UserDefaults.standard.set(current, forKey: restoreKey)
            PremiumDiag.note("sleep fade start: \(Int(left))s left, volume \(current)")
        }
        guard let start = startVolume else { return }
        // Ease out so the last stretch is the quietest part.
        let fraction = max(0, min(1, left / window))
        setVolume(start * Float(fraction * fraction))
    }

    private static func restore(_ volume: Float) {
        setVolume(volume)
        UserDefaults.standard.removeObject(forKey: restoreKey)
        PremiumDiag.note("sleep fade restored volume \(volume)")
    }

    private static func setVolume(_ value: Float) {
        if volumeView.window == nil {
            let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? UIApplication.shared.windows.first
            window?.addSubview(volumeView)
        }
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(value, animated: false)
        slider.sendActions(for: .valueChanged)
    }
}
