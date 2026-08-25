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

                ScrollView {
                    LazyVStack(spacing: 20) {
                        settingsSection(
                            title: "Appearance",
                            footer: "Choose the appearance used throughout the app."
                        ) {
                        Picker("Theme", selection: $themeSettings.appearance) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.displayName)
                                    .tag(appearance)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(AppTheme.accentPrimary)
                        }

                        settingsSection(
                            title: "Accent Color",
                            footer: "The brand accent is used for selection, progress, and primary actions."
                        ) {
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
                        }
                    }
                    .padding()
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
            .navigationTitle("Settings")
        }
    }

    private func settingsSection<Content: View>(
        title: LocalizedStringKey,
        footer: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()

            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard()
    }
}
