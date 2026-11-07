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
    }

    var body: some View {
        List {
            Section(
                header: Text("Eevee Home"),
                footer: Text("A redesigned top of Home: greeting, a now-playing card with controls, quick tiles for Liked Songs, Downloads, Recents, Queue, Sleep timer and Equalizer, and your pinned playlists. Tap the pin on the now-playing card to pin what's playing; long-press a pin to remove it.")
            ) {
                SettingsToggle(title: "Eevee Home", icon: "sparkles", color: .green, isOn: $options.eeveeHome)
                if options.eeveeHome {
                    SettingsToggle(title: "Greeting", icon: "sun.max.fill", color: .orange, isOn: $options.homeGreeting)
                    SettingsToggle(title: "Now playing card", icon: "play.rectangle.fill", color: .pink, isOn: $options.homeHero)
                    SettingsToggle(title: "Quick tiles", icon: "square.grid.3x2.fill", color: .blue, isOn: $options.homeTiles)
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
