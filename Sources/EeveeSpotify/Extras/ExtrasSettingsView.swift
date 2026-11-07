import SwiftUI

// One page for every Premium Edition extra. All of them are client-side only.
struct ExtrasSettingsView: View {
    @State private var options = UserDefaults.extrasOptions
    private let launched = ExtrasOptions.launch

    private var needsRestart: Bool {
        options.startupPage != launched.startupPage
            || options.eeveeHome != launched.eeveeHome
            || options.sleepFade != launched.sleepFade
            || options.hidePodcasts != launched.hidePodcasts
            || options.resumeOnLaunch != launched.resumeOnLaunch
            || options.offlineOpensDownloads != launched.offlineOpensDownloads
    }

    var body: some View {
        List {
            Section(
                header: Text("Eevee Home"),
                footer: Text("A redesigned top of Home: greeting, a now-playing card tinted from the artwork with progress and controls, quick tiles for Liked Songs, Downloads, Recents, Queue, Sleep timer and Equalizer, and your pinned playlists. Tap the pin on the card to pin what's playing; long-press a pin to move or remove it. Offline, Downloads moves to the front.")
            ) {
                SettingsToggle(title: "Eevee Home", icon: "sparkles", color: .green, isOn: $options.eeveeHome)
                if options.eeveeHome {
                    SettingsToggle(title: "Greeting", icon: "sun.max.fill", color: .orange, isOn: $options.homeGreeting)
                    SettingsToggle(title: "Now playing card", icon: "play.rectangle.fill", color: .pink, isOn: $options.homeHero)
                    SettingsToggle(title: "Quick tiles", icon: "square.grid.3x2.fill", color: .blue, isOn: $options.homeTiles)
                    if options.homeHero {
                        SettingsToggle(title: "Tint from artwork", icon: "paintpalette.fill", color: .purple, isOn: $options.homeArtworkTint)
                        SettingsToggle(title: "Long-press quick actions", icon: "hand.tap.fill", color: Color(red: 0.2, green: 0.7, blue: 0.75), isOn: $options.heroActions)
                    }
                    SettingsToggle(title: "Haptics", icon: "waveform", color: .gray, isOn: $options.homeHaptics)
                }
            }

            if !options.pinned.isEmpty {
                Section(header: Text("Pinned")) {
                    ForEach(options.pinned, id: \.uri) { item in
                        Label(item.title, systemImage: "pin.fill")
                    }
                    .onDelete { options.pinned.remove(atOffsets: $0) }
                    .onMove { options.pinned.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Section(
                header: Text("Sleep timer"),
                footer: Text("When Spotify's sleep timer is about to stop playback, the volume fades out smoothly instead of cutting off, then goes back to where it was. \"End of track\" timers fade over the last few seconds of the song. Set the timer from the Sleep timer tile on Home or the player's menu.")
            ) {
                SettingsToggle(title: "Fade out", icon: "moon.zzz.fill", color: .purple, isOn: $options.sleepFade)
                if options.sleepFade {
                    Picker("Fade length", selection: $options.sleepFadeSeconds) {
                        ForEach(ExtrasOptions.fadeChoices, id: \.self) { seconds in
                            Text(seconds < 60 ? "\(seconds) seconds" : "\(seconds / 60) min").tag(seconds)
                        }
                    }
                }
            }

            Section(
                header: Text("Music only"),
                footer: Text("Hides podcast and audiobook shelves and the Podcasts / Audiobooks filter pills on Home.")
            ) {
                SettingsToggle(title: "Hide podcasts & audiobooks", icon: "mic.slash.fill", color: .red, isOn: $options.hidePodcasts)
            }

            Section(
                header: Text("Quality of life"),
                footer: Text("Resume picks your last track back up when Spotify opens; with the headphone check on, it only does so through headphones, Bluetooth, AirPlay or a car, never the phone speaker. Keep screen on stops the phone sleeping while music plays and it's charging, handy on a nightstand or in the car. Long-press the now-playing card on Home to share or copy the song link, or jump to the artist, album or queue.")
            ) {
                SettingsToggle(title: "Resume on launch", icon: "play.circle.fill", color: .green, isOn: $options.resumeOnLaunch)
                if options.resumeOnLaunch {
                    SettingsToggle(title: "Only with headphones or car", icon: "headphones", color: .blue, isOn: $options.resumeNeedsHeadphones)
                }
                SettingsToggle(title: "Keep screen on while charging", icon: "bolt.fill", color: .yellow, isOn: $options.awakeWhileCharging)
                SettingsToggle(title: "Open Downloads when offline", icon: "wifi.slash", color: .orange, isOn: $options.offlineOpensDownloads)
            }

            Section(footer: Text("The Queue tile on Home opens Spotify's queue, where you can reorder, remove and clear upcoming tracks.")) {
                Label("Queue", systemImage: "list.bullet")
            }

            Section(
                header: Text("Startup"),
                footer: Text("restart_is_required_description".localized)
            ) {
                Picker("Open Spotify to", selection: $options.startupPage) {
                    ForEach(StartupPage.allCases, id: \.self) { page in
                        Text(page.title).tag(page)
                    }
                }
            }

            Section(footer: Text("Long-press a line in the custom lyrics view to copy it, or use the share button at the top to share the lyrics as text.")) {
                Label("Lyrics copy & share", systemImage: "quote.bubble")
            }

            RestartSection(visible: needsRestart)

            SpacerView()
        }
        .eeveeSettingsStyle()
        .onChange(of: options) { newValue in
            UserDefaults.extrasOptions = newValue
            NotificationCenter.default.post(name: .eeveeExtrasChanged, object: nil)
        }
    }
}
