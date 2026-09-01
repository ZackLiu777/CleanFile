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

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state") {
            let defaults = UserDefaults.standard
            for key in [
                "appAppearance",
                "appTheme",
                "appAccentPalette",
                "appCustomAccentColor",
                "appCustomBackgroundColor",
                "appCustomBackgroundStyle",
                "appUsesCustomBackground",
                "appLiquidGlassCardsEnabled",
                "appInterfaceAnimationsEnabled",
                "appMediaDateHeadersEnabled"
            ] {
                defaults.removeObject(forKey: key)
            }
        }
#endif
        _themeSettings = StateObject(wrappedValue: ThemeSettings())
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(themeSettings)
                .environment(\.appTheme, themeSettings.theme)
                .preferredColorScheme(themeSettings.effectiveColorScheme)
                .tint(themeSettings.theme.accentPrimary)
                .foregroundStyle(themeSettings.theme.textPrimary)
        }
    }

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-test-import-progress") {
            ConversionImportProgressUITestHarness()
        } else {
            ContentView()
        }
#else
        ContentView()
#endif
    }
}
