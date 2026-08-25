//
//  AppTheme.swift
//  CleanMyIPhone
//

import Combine
import Foundation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    var id: Self { self }

    var displayName: LocalizedStringKey {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class ThemeSettings: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet {
            userDefaults.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    private static let appearanceKey = "appAppearance"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        appearance = userDefaults.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init(rawValue:)) ?? .light
    }
}

enum AppTheme {
    static let accentPrimary = Color(
        red: 0xE8 / 255.0,
        green: 0xA3 / 255.0,
        blue: 0x9C / 255.0
    )

    static func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color]

        switch colorScheme {
        case .light:
            colors = [
                accentPrimary.opacity(0.16),
                accentPrimary.opacity(0.05),
                Color(.systemBackground)
            ]
        case .dark:
            colors = [
                Color(.systemBackground),
                accentPrimary.opacity(0.09),
                Color(.systemBackground)
            ]
        @unknown default:
            colors = [Color(.systemBackground)]
        }

        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func fileCategoryColor(_ category: FileCategory?) -> Color {
        switch category {
        case .video: accentPrimary
        case .image: Color(red: 0.95, green: 0.67, blue: 0.42)
        case .audio: Color(red: 0.66, green: 0.52, blue: 0.86)
        case .document: Color(red: 0.38, green: 0.63, blue: 0.90)
        case .pdf: Color(red: 0.88, green: 0.37, blue: 0.40)
        case .archive: Color(red: 0.34, green: 0.72, blue: 0.66)
        case .other, nil: Color.secondary
        }
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppTheme.backgroundGradient(for: colorScheme)
            .ignoresSafeArea()
    }
}

private struct AppGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            fallback(content)
        }
#else
        fallback(content)
#endif
    }

    private func fallback(_ content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            }
    }
}

extension View {
    func appGlassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(AppGlassCardModifier(cornerRadius: cornerRadius))
    }
}
