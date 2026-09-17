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
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var showsPremium = false
    @State private var showsHelp = false

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

                Section("Support") {
                    VStack(spacing: 0) {
                        Button {
                            showsHelp = true
                        } label: {
                            HStack(spacing: 12) {
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

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .accessibilityIdentifier("settings.help")

                        Divider()

                        Button {
                            guard let feedbackEmailURL else { return }
                            openURL(feedbackEmailURL)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Contact Developer")
                                    Text("Send feedback, questions, or bug reports by email.")
                                        .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                                        .foregroundStyle(theme.textSecondary)
                                }
                            } icon: {
                                Image(systemName: "envelope")
                                    .foregroundStyle(theme.accentPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("settings.contactDeveloper")
                    }
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
            .padding(.top, -24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
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
            .navigationDestination(isPresented: $showsHelp) {
                HelpView()
            }
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

    private var feedbackEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "liaozhengqiang8@gmail.com"
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: String(localized: "File Cleaner & Media Converter Feedback")
            )
        ]
        return components.url
    }

    /// 在设置主页准确显示当前使用的是预设背景还是用户自定义背景。
    private var selectedBackgroundName: LocalizedStringKey {
        themeSettings.usesCustomBackground
            ? "Custom"
            : themeSettings.selectedThemeID.displayName
    }
}
