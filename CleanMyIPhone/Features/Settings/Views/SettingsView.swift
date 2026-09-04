//
//  SettingsView.swift
//  CleanMyIPhone
//

//
//  文件职责：声明 Settings 界面结构、交互入口与展示状态。
//  所属模块：CleanMyIPhone。
//

import SwiftUI
import Photos
import UIKit

/// 定义 `SettingsView` 的值语义数据与相关行为。
struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var themeSettings: ThemeSettings
    @EnvironmentObject private var languageSettings: AppLanguageSettings
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showsPremium = false

    var body: some View {
        NavigationStack {
            List {
                Text("Settings")
                    .appTypeface(.largeTitle.bold(), size: 34, relativeTo: .largeTitle, weight: .bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(
                        EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                Section {
                    Button {
                        showsPremium = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CleanFile Premium")
                                    .foregroundStyle(theme.textPrimary)
                                Text("premium.entry.subtitle")
                                    .foregroundStyle(theme.textSecondary)
                                    .font(.caption)
                            }
                        } icon: {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(theme.accentPrimary)
                        }
                    }
                    .accessibilityIdentifier("settings.premium")
                }
                .appListCard()

                Section {
                    NavigationLink {
                        AppearanceThemeView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Appearance & Theme")
                                Text(selectedBackgroundName)
                                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(theme.accentPrimary)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text("Personalization")
                } footer: {
                    Text("Choose app colors, background, and appearance in one place.")
                }
                .appListCard()

                Section {
                    Picker(
                        "App Language",
                        selection: Binding(
                            get: { languageSettings.language },
                            set: { languageSettings.select($0) }
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            if language == .system {
                                Text("Follow System")
                                    .tag(language)
                            } else {
                                Text(verbatim: language.displayName)
                                    .tag(language)
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("settings.language")
                } header: {
                    Text("Language")
                } footer: {
                    Text("Language changes apply immediately throughout the app.")
                }
                .appListCard()

                Section("Support") {
                    NavigationLink {
                        HelpView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Help")
                                Text("Learn how to use the app and safely free up iPhone storage.")
                                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        } icon: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(theme.accentPrimary)
                        }
                    }
                    .accessibilityIdentifier("settings.help")
                }
                .appListCard()

                Section("Permissions") {
                    VStack(spacing: 0) {
                        LabeledContent {
                            Text(photoAccessDescription)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Photos", systemImage: "photo.on.rectangle")
                        }
                        .frame(minHeight: 50)

                        Divider()

                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            openURL(url)
                        } label: {
                            Label("Open System Settings", systemImage: "gear")
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        }
                    }
                }
                .appListCard()

                Section("Privacy") {
                    Label("Media and file analysis stays on this device.", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                }
                .appListCard()

                Section("About") {
                    VStack(spacing: 0) {
                        LabeledContent("Version", value: appVersion)
                            .frame(minHeight: 50)
                        Divider()
                        LabeledContent("Build", value: buildNumber)
                            .frame(minHeight: 50)
                    }
                }
                .appListCard()
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
        .accessibilityIdentifier("settings.screen")
        .sheet(isPresented: $showsPremium) {
            PremiumSubscriptionView()
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// 在设置主页准确显示当前使用的是预设背景还是用户自定义背景。
    private var selectedBackgroundName: LocalizedStringKey {
        themeSettings.usesCustomBackground
            ? "Custom"
            : themeSettings.selectedThemeID.displayName
    }
}
