// 应用入口和根场景的组装位置。
// 在这里建立共享状态并选择启动目标；具体功能与文件操作由各自模块负责。
// 根场景向下游注入主题、字体与权益对象，并组合首次介绍和应用主界面。
// 启动时清理旧语言覆盖；调试构建中的启动参数仅用于重置状态或展示指定预览。

//
//  CleanMyIPhoneApp.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//


import ImageFormatConversionKit
import SwiftUI

@main
/// 创建应用共享外观和权益状态，并组装根场景与启动流程。
struct CleanMyIPhoneApp: App {
    @StateObject private var themeSettings: ThemeSettings
    @StateObject private var premiumEntitlementStore: PremiumEntitlementStore

    /// 创建全局外观和权益状态，并清理旧语言偏好；调试启动参数可重置指定状态。
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
            AppThemeEnvironmentHost(settings: themeSettings) {
                FirstLaunchIntroductionContainer {
                    rootView
                }
            }
            .environmentObject(themeSettings)
            .fontDesign(themeSettings.fontStyle.inheritedDesign)
            .appFontFamily(themeSettings.fontStyle.fontName)
            .environmentObject(premiumEntitlementStore)
            .preferredColorScheme(themeSettings.effectiveColorScheme)
        }
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

/// 使用当前场景实际外观解析系统主题，避免系统动态颜色在子页面之间出现混合。
private struct AppThemeEnvironmentHost<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var settings: ThemeSettings
    @ViewBuilder var content: Content

    var body: some View {
        let resolvedTheme = settings.theme(for: colorScheme)
        content
            .environment(\.appTheme, resolvedTheme)
            .tint(resolvedTheme.accentPrimary)
            .foregroundStyle(resolvedTheme.textPrimary)
    }
}
