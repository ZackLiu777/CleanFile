//
//  SettingsView.swift
//  CleanMyIPhone
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var themeSettings: ThemeSettings

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                List {
                    Section {
                        Picker("Theme", selection: $themeSettings.appearance) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.displayName)
                                    .tag(appearance)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(AppTheme.accentPrimary)
                    } header: {
                        Text("Appearance")
                    } footer: {
                        Text("Choose the appearance used throughout the app.")
                    }

                    Section {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AppTheme.accentPrimary)
                                .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("CleanMyIPhone Pink")
                                Text("#E8A39C")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.accentPrimary)
                        }
                    } header: {
                        Text("Accent Color")
                    } footer: {
                        Text("The brand accent is used for selection, progress, and primary actions.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
        }
    }
}
