//
//  ContentView.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//

import ImageFormatConversionKit
import SwiftUI

private enum AppTab: String, Hashable {
    case photos
    case storage
    case conversion
    case settings
}

struct ContentView: View {
    @StateObject private var mediaViewModel = PhotoLibraryViewModel()
    @StateObject private var fileViewModel = FileScannerViewModel()
    @AppStorage("selectedAppTab") private var selectedTab: AppTab = .photos

    var body: some View {
        TabView(selection: $selectedTab) {
            PhotosView(viewModel: mediaViewModel)
                .tabItem {
                    Label("Media", systemImage: "photo.on.rectangle")
                }
                .tag(AppTab.photos)

            StorageView(viewModel: fileViewModel)
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(AppTab.storage)

            ImageConversionView()
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
        .toolbarBackground(.hidden, for: .tabBar)
        .tint(AppTheme.accentPrimary)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

#if DEBUG
// Keep the canvas preview stateless. The live root owns file-scanning and
// PhotoKit state objects that should only be attached by the running app.
#Preview("App Theme") {
    VStack(spacing: 16) {
        Image(systemName: "photo.on.rectangle")
            .font(.largeTitle)
            .foregroundStyle(AppTheme.accentPrimary)

        Text("CleanMyIPhone")
            .font(.title2.bold())

        Text("Run the app to choose a folder or access the photo library.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }
    .padding()
}
#endif
