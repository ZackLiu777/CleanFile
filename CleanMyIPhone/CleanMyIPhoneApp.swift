//
//  CleanMyIPhoneApp.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//

import ImageFormatConversionKit
import SwiftUI

@main
struct CleanMyIPhoneApp: App {
    @StateObject private var themeSettings = ThemeSettings()

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
