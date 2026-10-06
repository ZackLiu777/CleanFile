import ImageFormatConversionKit
import SwiftUI

struct PremiumAccessRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject var entitlementStore: PremiumEntitlementStore
    @StateObject private var accessStore: PremiumFeatureAccessStore

    init(entitlementStore: PremiumEntitlementStore) {
        self.entitlementStore = entitlementStore
        let state: PremiumEntitlementStore.AccessState = PremiumConfiguration.bypassesEntitlementForUITesting
            ? .entitled : PremiumConfiguration.usesFreeTierForUITesting ? .notEntitled : entitlementStore.accessState
        _accessStore = StateObject(wrappedValue: PremiumFeatureAccessStore(accessState: state))
    }

    var body: some View {
        ContentView(accessStore: accessStore)
            .environmentObject(accessStore)
            .environment(\.conversionUsagePolicy, accessStore.conversionPolicy)
            .task {
                synchronizeAccess()
                guard !PremiumConfiguration.bypassesEntitlementForUITesting,
                      !PremiumConfiguration.usesFreeTierForUITesting else { return }
                await entitlementStore.start()
            }
            .onChange(of: entitlementStore.accessState) { _, _ in synchronizeAccess() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active,
                      !PremiumConfiguration.bypassesEntitlementForUITesting,
                      !PremiumConfiguration.usesFreeTierForUITesting else { return }
                Task { await entitlementStore.refresh() }
            }
    }

    private func synchronizeAccess() {
        if !PremiumConfiguration.bypassesEntitlementForUITesting,
           !PremiumConfiguration.usesFreeTierForUITesting {
            accessStore.update(entitlementStore.accessState)
        }
        themeSettings.setPremiumAppearanceAllowed(accessStore.preservesPremiumAppearance)
    }
}
