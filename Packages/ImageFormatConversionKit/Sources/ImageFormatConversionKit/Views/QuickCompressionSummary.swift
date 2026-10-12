import SwiftUI

/// A preset shortcut shares the converter's import and output handling.
struct QuickCompressionSummary: View {
    let kind: ConversionUsageCategory
    @Environment(\.conversionTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("quick.ready"), systemImage: "checkmark.circle")
                .font(.headline)
            Text(L10n.string(kind == .video ? "quick.video.detail" : "quick.image.detail"))
                .font(.subheadline)
            Text(L10n.string("quick.originals"))
                .font(.footnote)
                .foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversion.quickPreset")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.cardElevated, in: RoundedRectangle(cornerRadius: 18))
    }
}
