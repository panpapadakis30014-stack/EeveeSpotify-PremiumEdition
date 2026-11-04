import SwiftUI

// One page for every Premium Edition extra. All of them are client-side only.
struct ExtrasSettingsView: View {
    @State private var options = UserDefaults.extrasOptions

    var body: some View {
        List {
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

            SpacerView()
        }
        .eeveeSettingsStyle()
        .onChange(of: options) { newValue in
            UserDefaults.extrasOptions = newValue
        }
    }
}
