import ImageFormatConversionKit
import SwiftUI

struct PremiumAccessRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appOpeningCompleted) private var openingCompleted
    @EnvironmentObject private var themeSettings: ThemeSettings
    @ObservedObject var entitlementStore: PremiumEntitlementStore
    @StateObject private var accessStore: PremiumFeatureAccessStore
    @State private var entryPresentation = PremiumEntryPresentation()
    @State private var showsEntryPremium = false
    @State private var entryVerified = false

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
            .sheet(isPresented: $showsEntryPremium) {
                PremiumSubscriptionView(allowsDismiss: true)
            }
            .task(id: scenePhase) {
                synchronizeAccess()
                guard scenePhase == .active, !skipsEntryPremium else { return }
                await entitlementStore.start()
                guard !Task.isCancelled, scenePhase == .active else { return }
                entryVerified = true
                presentEntryPremiumIfNeeded()
            }
            .onChange(of: openingCompleted) { _, _ in
                presentEntryPremiumIfNeeded()
            }
            .onChange(of: entitlementStore.accessState) { _, state in
                synchronizeAccess()
                if state == .entitled { showsEntryPremium = false }
                presentEntryPremiumIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    entryVerified = false
                }
            }
    }

    private var skipsEntryPremium: Bool {
        PremiumConfiguration.bypassesEntitlementForUITesting || PremiumConfiguration.usesFreeTierForUITesting
    }

    private func presentEntryPremiumIfNeeded() {
        guard !skipsEntryPremium, scenePhase == .active, entryVerified else { return }
        if entryPresentation.consumePresentation(for: entitlementStore.accessState, openingCompleted: openingCompleted) {
            showsEntryPremium = true
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

/// The offer is consumed once for this root lifetime; foreground transitions do not reset it.
@MainActor
struct PremiumEntryPresentation {
    private var hasPresented = false

    mutating func consumePresentation(for state: PremiumEntitlementStore.AccessState, openingCompleted: Bool = true) -> Bool {
        guard openingCompleted, state == .notEntitled, !hasPresented else { return false }
        hasPresented = true
        return true
    }
}
