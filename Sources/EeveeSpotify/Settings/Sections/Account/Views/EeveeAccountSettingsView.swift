import SwiftUI
import UIKit

// Replaces the old "Patching" page. Premium Edition never patches the account;
// this page only shows what Spotify reports for the signed-in subscription.
struct EeveeAccountSettingsView: View {
    @State var trueShuffleEnabled = UserDefaults.trueShuffleEnabled

    private var statusText: String {
        switch PremiumGate.status {
        case .premium:    return "Spotify Premium (verified)"
        case .notPremium: return "No active Premium subscription"
        case .unknown:    return "Not verified yet"
        }
    }

    private var statusColor: Color {
        switch PremiumGate.status {
        case .premium:    return .green
        case .notPremium: return .red
        case .unknown:    return .gray
        }
    }

    var body: some View {
        List {
            Section(
                footer: Text("EeveeSpotify Premium Edition only runs on accounts that already pay for Spotify Premium. It reads the subscription type Spotify reports at startup and never changes it.")
            ) {
                HStack {
                    Text("Subscription")
                    Spacer()
                    Text(statusText)
                        .foregroundColor(statusColor)
                }
            }

            Section(
                footer: Text(
                    "true_shuffle_dec".localized
                    + "restart_is_required_description".localized
                )
            ) {
                Toggle("true_shuffle".localized, isOn: $trueShuffleEnabled)
            }
            .onChange(of: trueShuffleEnabled) { isEnabled in
                UserDefaults.trueShuffleEnabled = isEnabled
            }

            SpacerView()
        }
        .eeveeSettingsStyle()
    }
}
