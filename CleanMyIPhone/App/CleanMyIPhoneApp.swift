//
//  CleanMyIPhoneApp.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//

//
//  文件职责：集中定义 CleanMyIPhoneApp 相关的生产逻辑与共享能力。
//  所属模块：CleanMyIPhone。
//

import ImageFormatConversionKit
import SwiftUI

@main
/// 定义 `CleanMyIPhoneApp` 的值语义数据与相关行为。
struct CleanMyIPhoneApp: App {
    @StateObject private var themeSettings: ThemeSettings
    @StateObject private var premiumEntitlementStore: PremiumEntitlementStore

    init() {
        let defaults = UserDefaults.standard
        // The app now follows iOS language exclusively. Remove any legacy override.
        defaults.removeObject(forKey: "appLanguageOverride")
#if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        if !defaults.bool(forKey: "hasPreviewedIntroductionRevisionTwo") {
            // Show this local development revision once on the connected phone.
            defaults.set(false, forKey: "hasCompletedFirstLaunchIntroduction")
            defaults.set(true, forKey: "hasPreviewedIntroductionRevisionTwo")
        }
        if launchArguments.contains("--preview-onboarding") {
            defaults.set(false, forKey: "hasCompletedFirstLaunchIntroduction")
        }
        if launchArguments.contains("--ui-testing-reset-state") {
            for key in [
                "appAppearance",
                "appTheme",
                "appAccentPalette",
                "appCustomAccentColor",
                "appCustomBackgroundColor",
                "appCustomBackgroundStyle",
                "appUsesCustomBackground",
                "appLiquidGlassCardsEnabled",
                "appCustomTabBarEnabled",
                "appInterfaceAnimationsEnabled",
                "appMediaDateHeadersEnabled",
                "selectedAppTab"
            ] {
                defaults.removeObject(forKey: key)
            }
        }
        if launchArguments.contains("--ui-testing-system-theme") {
            defaults.set(AppThemeID.system.rawValue, forKey: "appTheme")
        }
        if launchArguments.contains("--ui-testing-liquid-glass") {
            defaults.set(true, forKey: "appLiquidGlassCardsEnabled")
        }
#endif
        _themeSettings = StateObject(wrappedValue: ThemeSettings())
        _premiumEntitlementStore = StateObject(wrappedValue: PremiumEntitlementStore())
    }

    var body: some Scene {
        WindowGroup {
            AppOpeningContainer(destination: launchDestination) {
                FirstLaunchIntroductionContainer {
                    rootView
                }
            }
            .environmentObject(themeSettings)
            .fontDesign(themeSettings.fontStyle.inheritedDesign)
            .appFontFamily(themeSettings.fontStyle.fontName)
            .environmentObject(premiumEntitlementStore)
            .environment(\.appTheme, themeSettings.theme)
            .preferredColorScheme(themeSettings.effectiveColorScheme)
            .tint(themeSettings.theme.accentPrimary)
            .foregroundStyle(themeSettings.theme.textPrimary)
        }
    }

    private var launchDestination: AppLaunchState.Destination {
        // Free features are immediately available; StoreKit verification runs independently.
        .ready
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-import-progress") {
            ConversionImportProgressUITestHarness()
        } else if ProcessInfo.processInfo.arguments.contains("--ui-test-conversion-action-bar") {
            ConversionActionBarUITestHarness(theme: themeSettings.theme.conversionTheme)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-test-replacement-review") {
            ConversionReplacementReviewUITestHarness()
        } else {
            PremiumAccessRootView(entitlementStore: premiumEntitlementStore)
        }
#else
        PremiumAccessRootView(entitlementStore: premiumEntitlementStore)
#endif
    }
}
