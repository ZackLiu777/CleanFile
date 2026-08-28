//
//  SettingsView.swift
//  CleanMyIPhone
//

import SwiftUI
import Photos
import UIKit

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var themeSettings: ThemeSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        NavigationStack {
            List {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(
                        EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                Section("Color Theme") {
                    Picker("Color Theme", selection: $themeSettings.selectedThemeID) {
                        ForEach(AppThemeID.allCases) { themeID in
                            Text(themeID.displayName)
                                .tag(themeID)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                .listRowBackground(theme.cardSurface)

                Section {
                    Picker("Appearance", selection: $themeSettings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName)
                                .tag(appearance)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(theme.preferredColorScheme != nil)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text(appearanceFooter)
                }
                .listRowBackground(theme.cardSurface)

                Section("Permissions") {
                    LabeledContent {
                        Text(photoAccessDescription)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }

                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else {
                            return
                        }
                        openURL(url)
                    } label: {
                        Label("Open System Settings", systemImage: "gear")
                    }
                }
                .listRowBackground(theme.cardSurface)

                Section("Privacy") {
                    Label("Media and file analysis stays on this device.", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(theme.cardSurface)

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }
                .listRowBackground(theme.cardSurface)
            }
            .contentMargins(.horizontal, 4, for: .scrollContent)
            .contentMargins(.top, -24, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .appSoftScrollEdge()
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            }
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var photoAccessDescription: LocalizedStringKey {
        switch photoAuthorizationStatus {
        case .authorized: "Full Access"
        case .limited: "Limited Access"
        case .denied, .restricted: "No Access"
        case .notDetermined: "Not Requested"
        @unknown default: "No Access"
        }
    }

    private var appearanceFooter: LocalizedStringKey {
        theme.preferredColorScheme == nil
            ? "Choose the appearance used throughout the app."
            : "This color theme uses a fixed appearance."
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
