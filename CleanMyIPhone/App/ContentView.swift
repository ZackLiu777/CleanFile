//
//  ContentView.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//

//
//  文件职责：声明 Content 界面结构、交互入口与展示状态。
//  所属模块：CleanMyIPhone。
//

import ImageFormatConversionKit
import SwiftUI

/// 定义 `AppTab` 使用的有限状态或选项集合。
private enum AppTab: String, Hashable {
    case photos
    case storage
    case conversion
    case settings
}

/// 定义 `ContentView` 的值语义数据与相关行为。
struct ContentView: View {
    @Environment(\.appTheme) private var theme
    @StateObject private var mediaViewModel = PhotoLibraryViewModel()
    @StateObject private var fileViewModel = FileScannerViewModel()
    @AppStorage("selectedAppTab") private var selectedTab: AppTab = .photos

    var body: some View {
        TabView(selection: $selectedTab) {
            PhotosView(
                viewModel: mediaViewModel,
                isTabActive: selectedTab == .photos
            )
                .tabItem {
                    Label("Media", systemImage: "photo.on.rectangle")
                }
                .tag(AppTab.photos)

            StorageView(
                viewModel: fileViewModel,
                isTabActive: selectedTab == .storage
            )
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(AppTab.storage)

            ConversionHomeView(
                theme: theme.conversionTheme,
                isTabActive: selectedTab == .conversion
            )
                .tabItem {
                    Label("Convert", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(AppTab.conversion)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
        .tint(theme.accentPrimary)
        .toolbarBackground(.hidden, for: .tabBar)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

/// 扩展 `Theme`，集中实现当前文件所需的附加能力。
private extension Theme {
    var conversionTheme: ConversionTheme {
        ConversionTheme(
            background: conversionBackground,
            cardSurface: cardSurface,
            cardElevated: cardElevated,
            cardHighlight: backgroundSecondary,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            accent: accentPrimary,
            destructive: negativeRed,
            divider: divider,
            liquidGlassEnabled: liquidGlassEnabled
        )
    }

    var conversionBackground: ConversionBackground {
        switch background {
        case let .solid(color):
            .solid(color)
        case let .linearGradient(colors, startPoint, endPoint):
            .linearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
        }
    }
}

#if DEBUG
// Keep the canvas preview stateless. The live root owns file-scanning and
// PhotoKit state objects that should only be attached by the running app.
#Preview("App Theme") {
    VStack(spacing: 16) {
        Image(systemName: "photo.on.rectangle")
            .font(.largeTitle)
            .foregroundStyle(Theme.system.accentPrimary)

        Text("CleanMyIPhone")
            .font(.title2.bold())

        Text("Run the app to choose a folder or access the photo library.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
    .padding()
}
#endif
