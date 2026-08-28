//
//  文件职责：集中定义 ConversionFormatWheelPicker 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI

/// 定义 `ConversionFormatOption` 的值语义数据与相关行为。
struct ConversionFormatOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let detail: String

    var id: Value { value }
}

/// 定义 `ConversionFormatWheelPicker` 的值语义数据与相关行为。
struct ConversionFormatWheelPicker<Value: Hashable>: View {
    @Environment(\.conversionTheme) private var theme
    @Binding var selection: Value
    let options: [ConversionFormatOption<Value>]
    @State private var isPresented = false

    private var selectedOption: ConversionFormatOption<Value>? {
        options.first { $0.value == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isPresented = true
            } label: {
                HStack(spacing: 8) {
                    Text(selectedOption?.title ?? "")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)

            if let selectedOption {
                Label(selectedOption.detail, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Picker("", selection: $selection) {
                    ForEach(options) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .padding(.horizontal)
                .navigationTitle(L10n.string("format_picker.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.string("format_picker.done")) {
                            isPresented = false
                        }
                    }
                }
            }
            .presentationDetents([.height(330), .medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Presents related conversion settings as one clock-style multi-column wheel.
/// Each conversion screen owns its strongly typed bindings; this component only
/// coordinates the shared trigger, summary, sheet, and layout.
struct ConversionSettingsWheelPicker<WheelContent: View>: View {
    @Environment(\.conversionTheme) private var theme
    let summary: String
    let detail: String?
    @ViewBuilder let wheelContent: () -> WheelContent
    @State private var isPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isPresented = true
            } label: {
                Text(summary)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(ConversionSettingsTriggerButtonStyle(accent: theme.accent))
            .accessibilityHint(L10n.string("settings.title"))

            if let detail, !detail.isEmpty {
                Label(detail, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                wheelContent()
                    .padding(.horizontal, 8)
                    .navigationTitle(L10n.string("settings.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L10n.string("format_picker.done")) {
                                isPresented = false
                            }
                        }
                    }
            }
            .presentationDetents([.height(350), .medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// 定义 `ConversionSettingsTriggerButtonStyle` 的值语义数据与相关行为。
private struct ConversionSettingsTriggerButtonStyle: ButtonStyle {
    let accent: Color

    /// 创建 `makeBody` 所需的值或资源，统一封装构造细节。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                accent.opacity(configuration.isPressed ? 0.18 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// 定义 `ConversionWheelColumn` 的值语义数据与相关行为。
struct ConversionWheelColumn<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Picker(title, selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.wheel)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}
