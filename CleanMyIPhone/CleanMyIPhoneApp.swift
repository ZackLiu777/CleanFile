//
//  CleanMyIPhoneApp.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//

import SwiftUI

@main
struct CleanMyIPhoneApp: App {
    @StateObject private var themeSettings = ThemeSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeSettings)
                .preferredColorScheme(themeSettings.appearance.colorScheme)
                .tint(AppTheme.accentPrimary)
        }
    }
}
