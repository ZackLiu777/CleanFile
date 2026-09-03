import SwiftUI

/// A live, localized representation of the conversion screens. Unlike a bitmap
/// screenshot, this stays readable when the app language or text size changes.
struct ConversionGuideLocalizedPreview: View {
    @Environment(\.conversionTheme) private var theme

    let imageName: String

    private var selectedTool: String? {
        for tool in ["image", "video", "audio"] where imageName.hasSuffix(tool) {
            return tool
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedTool.map(toolTitle) ?? L10n.string("conversion.guide.title"))
                    .appTypeface(.title3.bold(), size: 20, relativeTo: .title3, weight: .bold)
                    .lineLimit(1)

                Spacer()

                Image(systemName: selectedTool.map(toolSymbol) ?? "lightbulb")
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                    .foregroundStyle(theme.accent)
                    .frame(width: 34, height: 34)
                    .background(theme.accent.opacity(0.12), in: Circle())
            }

            if let selectedTool {
                toolPreview(selectedTool)
            } else {
                ForEach(["image", "video", "audio"], id: \.self) { tool in
                    previewRow(
                        symbol: toolSymbol(tool),
                        title: toolTitle(tool),
                        detail: L10n.dynamicString("conversion.home.\(tool).tagline")
                    )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(theme.cardElevated)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func toolPreview(_ tool: String) -> some View {
        previewRow(
            symbol: toolSymbol(tool),
            title: L10n.string("conversion.guide.detail.purpose.title"),
            detail: L10n.dynamicString("conversion.guide.\(tool).detail")
        )

        Divider().overlay(theme.divider)

        HStack(spacing: 8) {
            previewTag(L10n.string("settings.format"))
            previewTag(L10n.string("settings.quality"))
            previewTag(L10n.string("settings.output"))
        }
    }

    private func previewRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: symbol)
                .appTypeface(.system(size: 16, weight: .semibold), size: 16, relativeTo: .body, weight: .semibold)
                .foregroundStyle(theme.accent)
                .frame(width: 34, height: 34)
                .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)
                    .lineLimit(1)
                Text(detail)
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private func previewTag(_ title: String) -> some View {
        Text(title)
            .appTypeface(.caption2.weight(.semibold), size: 11, relativeTo: .caption2, weight: .semibold)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(theme.accent.opacity(0.10), in: Capsule())
    }

    private func toolTitle(_ tool: String) -> String {
        L10n.dynamicString("conversion.home.\(tool).title")
    }

    private func toolSymbol(_ tool: String) -> String {
        switch tool {
        case "image": "photo.on.rectangle.angled"
        case "video": "film.stack"
        default: "waveform"
        }
    }
}
