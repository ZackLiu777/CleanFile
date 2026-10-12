import SwiftUI

/// The shared action button used by professional conversion and media quick compression.
@MainActor
public struct ConversionActionButton: View {
    private let title: String
    private let systemImage: String
    private let accentColor: Color
    private let foregroundColor: Color
    private let action: () -> Void

    public init(
        title: String,
        systemImage: String = "arrow.triangle.2.circlepath",
        accentColor: Color,
        foregroundColor: Color,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accentColor = accentColor
        self.foregroundColor = foregroundColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .black))
                Text(title.uppercased())
                    .appTypeface(.subheadline.weight(.black), size: 14, relativeTo: .subheadline, weight: .black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
        .buttonStyle(ConversionPhysicalActionButtonStyle(faceColor: accentColor, edgeColor: foregroundColor))
    }
}
