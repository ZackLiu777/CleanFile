//
//  ConversionGuideView.swift
//
//  文件职责：以可浏览的提示集合介绍转换功能的真实用户流程。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI

@MainActor
struct ConversionGuideView: View {
    @Environment(\.conversionTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath: [ConversionGuideTool]

    init() {
        _navigationPath = State(initialValue: ConversionGuideTool.initialDebugPath)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ConversionGuideHero()

                    ConversionGuideSection(
                        title: L10n.string("conversion.guide.steps.title")
                    ) {
                        VStack(spacing: 0) {
                            ConversionGuideStep(
                                number: 1,
                                title: L10n.string("conversion.guide.step.choose.title"),
                                detail: L10n.string("conversion.guide.step.choose.detail")
                            )

                            Divider()
                                .padding(.leading, 58)

                            ConversionGuideStep(
                                number: 2,
                                title: L10n.string("conversion.guide.step.adjust.title"),
                                detail: L10n.string("conversion.guide.step.adjust.detail")
                            )

                            Divider()
                                .padding(.leading, 58)

                            ConversionGuideStep(
                                number: 3,
                                title: L10n.string("conversion.guide.step.convert.title"),
                                detail: L10n.string("conversion.guide.step.convert.detail")
                            )
                        }
                        .padding(.horizontal, 16)
                        .converterCard()

                        ConversionGuideScreenshotCard(
                            imageName: "conversion-guide-home",
                            symbol: "square.grid.2x2",
                            title: L10n.string("conversion.guide.home.title"),
                            detail: L10n.string("conversion.guide.home.detail")
                        )
                    }

                    ConversionGuideSection(
                        title: L10n.string("conversion.guide.tools.title")
                    ) {
                        ForEach(ConversionGuideTool.allCases) { tool in
                            NavigationLink(value: tool) {
                                ConversionGuideScreenshotCard(
                                    imageName: tool.imageName,
                                    symbol: tool.symbol,
                                    title: tool.title,
                                    detail: tool.overview,
                                    showsDisclosure: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ConversionGuideSection(
                        title: L10n.string("conversion.guide.controls.title")
                    ) {
                        VStack(spacing: 0) {
                            ConversionGuideFeature(
                                symbol: "doc.badge.gearshape",
                                title: L10n.string("settings.format"),
                                detail: L10n.string("conversion.guide.format.detail")
                            )

                            Divider()
                                .padding(.leading, 54)

                            ConversionGuideFeature(
                                symbol: "slider.horizontal.3",
                                title: L10n.string("conversion.guide.quality.title"),
                                detail: L10n.string("conversion.guide.quality.detail")
                            )

                            Divider()
                                .padding(.leading, 54)

                            ConversionGuideFeature(
                                symbol: "location.slash",
                                title: L10n.string("settings.metadata"),
                                detail: L10n.string("conversion.guide.metadata.detail")
                            )
                        }
                        .padding(.horizontal, 16)
                        .converterCard()
                    }

                    ConversionGuidePrivacyCard()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .converterSoftScrollEdge()
            .background(converterBackground)
            .navigationTitle(L10n.string("conversion.guide.title"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .navigationDestination(for: ConversionGuideTool.self) { tool in
                ConversionGuideToolDetailView(tool: tool)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("action.done")) {
                        dismiss()
                    }
                }
            }
        }
        .tint(theme.accent)
        .foregroundStyle(theme.textPrimary)
    }

    @ViewBuilder
    private var converterBackground: some View {
        ConversionBackgroundView(background: theme.background)
            .ignoresSafeArea()
    }
}

private struct ConversionGuideHero: View {
    @Environment(\.conversionTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.accent.opacity(0.30),
                            theme.cardHighlight,
                            theme.cardSurface
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(theme.accent.opacity(0.18))
                .frame(width: 170, height: 170)
                .offset(x: 220, y: -94)

            Circle()
                .fill(theme.cardElevated.opacity(0.75))
                .frame(width: 118, height: 118)
                .offset(x: 154, y: -136)

            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 68, height: 68)
                    .background(
                        theme.cardSurface.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 7) {
                    Text(L10n.string("conversion.guide.hero.title"))
                        .font(.title.bold())
                        .foregroundStyle(theme.textPrimary)

                    Text(L10n.string("conversion.guide.hero.detail"))
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
        .frame(minHeight: 270)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(theme.divider.opacity(0.45), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ConversionGuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
    }
}

private struct ConversionGuideStep: View {
    @Environment(\.conversionTheme) private var theme
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(theme.accent)
                .frame(width: 36, height: 36)
                .background(theme.accent.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct ConversionGuideScreenshotCard: View {
    @Environment(\.conversionTheme) private var theme
    let imageName: String
    let symbol: String
    let title: String
    let detail: String
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(imageName, bundle: .module)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 230, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, theme.cardSurface.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 38)
                }
                .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 20, height: 36)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)

            if showsDisclosure {
                HStack(spacing: 6) {
                    Text(L10n.string("conversion.guide.learn_more"))
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .converterCard()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ConversionGuideFeature: View {
    @Environment(\.conversionTheme) private var theme
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct ConversionGuidePrivacyCard: View {
    @Environment(\.conversionTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 52, height: 52)
                .background(theme.accent.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("conversion.guide.privacy.title"))
                    .font(.title3.bold())

                Text(L10n.string("conversion.guide.privacy.detail"))
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .converterAccentCard()
        .accessibilityElement(children: .combine)
    }
}
