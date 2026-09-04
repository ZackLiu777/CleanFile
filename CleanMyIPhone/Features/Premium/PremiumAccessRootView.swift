import SwiftUI

struct PremiumAccessRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var entitlementStore: PremiumEntitlementStore

    var body: some View {
        Group {
            if PremiumConfiguration.bypassesEntitlementForUITesting {
                ContentView()
            } else {
                switch entitlementStore.accessState {
                case .checking:
                    ZStack {
                        AppBackground()
                        ProgressView()
                            .controlSize(.large)
                            .accessibilityLabel("premium.entitlement.checking")
                    }
                case .entitled:
                    ContentView()
                case .notEntitled:
                    PremiumSubscriptionView(allowsDismiss: false)
                }
            }
        }
        .task {
            guard !PremiumConfiguration.bypassesEntitlementForUITesting else { return }
            await entitlementStore.start()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active,
                  !PremiumConfiguration.bypassesEntitlementForUITesting else { return }
            Task { await entitlementStore.refresh() }
        }
    }
}
