import SwiftUI

// One page for every Premium Edition extra. All of them are client-side only.
struct ExtrasSettingsView: View {
    @State private var options = UserDefaults.extrasOptions
    @State private var paused = ExtrasSafety.isPaused
    @State private var confirmReset = false
    @State private var didReset = false
    private let launched = ExtrasOptions.launch

    private var needsRestart: Bool {
        options.startupPage != launched.startupPage
            || options.eeveeHome != launched.eeveeHome
            || options.sleepFade != launched.sleepFade
            || options.hidePodcasts != launched.hidePodcasts
            || options.resumeOnLaunch != launched.resumeOnLaunch
            || options.offlineOpensDownloads != launched.offlineOpensDownloads
            || (ExtrasSafety.safeMode && !paused)
    }

    var body: some View {
        List {
            if ExtrasSafety.safeMode {
                Section(
                    header: Text("Safe mode"),
                    footer: Text(paused
                        ? "Spotify closed right after opening twice in a row, so Premium Extras (Eevee Home, sleep fade, quality of life) were paused to keep Spotify working. Turn them back on to try again."
                        : "Premium Extras come back on after a restart.")
                ) {
                    if paused {
                        Button {
                            ExtrasSafety.resume()
                            paused = false
                        } label: {
                            Label("Turn Premium Extras back on", systemImage: "arrow.clockwise.circle.fill")
                        }
                    }
                }
            }

            Section(
                header: Text("Eevee Home"),
                footer: Text("A redesigned top of Home: greeting, a now-playing card tinted from the artwork, quick tiles, Jump back in, your pinned playlists and your listening time. Choose and reorder the sections in Home layout.")
            ) {
                SettingsToggle(title: "Eevee Home", icon: "sparkles", color: .green, isOn: $options.eeveeHome)
                if options.eeveeHome {
                    NavigationLink(destination: EeveeHomeLayoutView(options: $options)) {
                        HStack(spacing: 12) {
                            SettingsIcon(systemName: "rectangle.3.offgrid.fill", color: .blue)
                            Text("Home layout")
                            Spacer()
                            Text("\(HomeSection.allCases.filter(options.shows).count) of \(HomeSection.allCases.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                    if options.homeHero {
                        SettingsToggle(title: "Tint from artwork", icon: "paintpalette.fill", color: .purple, isOn: $options.homeArtworkTint)
                        SettingsToggle(title: "Long-press quick actions", icon: "hand.tap.fill", color: Color(red: 0.2, green: 0.7, blue: 0.75), isOn: $options.heroActions)
                    }
                    SettingsToggle(title: "Haptics", icon: "waveform", color: .gray, isOn: $options.homeHaptics)
                }
            }

            if !options.pinned.isEmpty {
                Section(header: Text("Pinned"), footer: Text("Swipe to remove. Long-press a pin on Home to move it to the front.")) {
                    ForEach(options.pinned, id: \.uri) { item in
                        Label(item.title, systemImage: "pin.fill")
                    }
                    .onDelete { options.pinned.remove(atOffsets: $0) }
                    .onMove { options.pinned.move(fromOffsets: $0, toOffset: $1) }
                }
            }

            Section(
                header: Text("Listening history"),
                footer: Text("Kept only on this phone: the playlists, albums and artists you play (for Jump back in) and how long you listen each day (for Your listening). Nothing is uploaded. Turning it off stops recording and hides both sections.")
            ) {
                SettingsToggle(title: "Record on this phone", icon: "chart.bar.fill", color: .orange, isOn: $options.recordListening)
                Button {
                    confirmReset = true
                } label: {
                    Label(didReset ? "History cleared" : "Clear history and stats", systemImage: didReset ? "checkmark.circle.fill" : "trash")
                        .foregroundColor(didReset ? .secondary : .red)
                }
                .disabled(didReset)
                .alert(isPresented: $confirmReset) {
                    Alert(
                        title: Text("Clear listening history?"),
                        message: Text("Jump back in and Your listening start over. This can't be undone."),
                        primaryButton: .destructive(Text("Clear")) {
                            ListeningLog.reset()
                            didReset = true
                        },
                        secondaryButton: .cancel()
                    )
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
                footer: Text("Resume picks your last track back up when Spotify opens; with the headphone check on, only through headphones, Bluetooth, AirPlay or a car, never the phone speaker. Keep screen on stops the phone sleeping while music plays and it's charging, handy on a nightstand or in the car, and while the lyrics view is open. Tab haptics give a light tick when you switch tabs on the Liquid Glass tab bar (icon-only labels and hiding tabs such as Create are under Customization → Tab bar).")
            ) {
                SettingsToggle(title: "Resume on launch", icon: "play.circle.fill", color: .green, isOn: $options.resumeOnLaunch)
                if options.resumeOnLaunch {
                    SettingsToggle(title: "Only with headphones or car", icon: "headphones", color: .blue, isOn: $options.resumeNeedsHeadphones)
                }
                SettingsToggle(title: "Keep screen on while charging", icon: "bolt.fill", color: .yellow, isOn: $options.awakeWhileCharging)
                SettingsToggle(title: "Keep screen on with lyrics open", icon: "quote.bubble.fill", color: .pink, isOn: $options.lyricsAwake)
                SettingsToggle(title: "Open Downloads when offline", icon: "wifi.slash", color: .orange, isOn: $options.offlineOpensDownloads)
                SettingsToggle(title: "Tab haptics", icon: "hand.point.up.left.fill", color: .gray, isOn: $options.tabHaptics)
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

// Which Eevee Home sections show, and in what order.
struct EeveeHomeLayoutView: View {
    @Binding var options: ExtrasOptions

    private func binding(for section: HomeSection) -> Binding<Bool> {
        switch section {
        case .greeting: return $options.homeGreeting
        case .nowPlaying: return $options.homeHero
        case .shortcuts: return $options.homeTiles
        case .recents: return $options.homeRecents
        case .pinned: return $options.homePinned
        case .stats: return $options.homeStats
        }
    }

    private func note(for section: HomeSection) -> String? {
        switch section {
        case .recents, .stats: return options.recordListening ? nil : "Needs listening history"
        case .pinned: return options.pinned.isEmpty ? "Shows once you pin something" : nil
        default: return nil
        }
    }

    var body: some View {
        List {
            Section(footer: Text("Drag the handles to reorder. Switched-off sections are hidden; Jump back in and Pinned also stay hidden until they have something in them.")) {
                ForEach(options.orderedSections, id: \.self) { section in
                    Toggle(isOn: binding(for: section)) {
                        HStack(spacing: 12) {
                            SettingsIcon(systemName: section.icon, color: .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title)
                                if let note = note(for: section) {
                                    Text(note).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .onMove { from, to in
                    var order = options.orderedSections
                    order.move(fromOffsets: from, toOffset: to)
                    options.homeOrder = order
                }
            }

            Section {
                Button("Reset to default order") {
                    options.homeOrder = HomeSection.allCases
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .eeveeSettingsStyle()
        .navigationTitle("Home layout")
    }
}
