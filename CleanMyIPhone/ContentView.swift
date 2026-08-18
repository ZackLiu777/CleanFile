//
//  ContentView.swift
//  CleanMyIPhone
//
//  Created by Zane Liao on 8/18/26.
//

import SwiftUI

private enum AppTab: Hashable {
    case photos
    case storage
    case settings
}

struct ContentView: View {
    @StateObject private var viewModel = FileScannerViewModel()
    @State private var selectedTab: AppTab = .photos

    var body: some View {
        TabView(selection: $selectedTab) {
            PhotosView()
                .tabItem {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .tag(AppTab.photos)

            StorageView(viewModel: viewModel)
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(AppTab.storage)

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
