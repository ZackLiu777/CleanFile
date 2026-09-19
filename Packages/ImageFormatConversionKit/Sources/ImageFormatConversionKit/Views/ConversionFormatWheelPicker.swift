//
//  文件职责：集中定义 ConversionFormatWheelPicker 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI
import UIKit

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
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
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
struct ConversionWheelColumn<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let optionTitle: (Selection) -> String

    init(
        title: String,
        selection: Binding<Selection>,
        options: [Selection],
        optionTitle: @escaping (Selection) -> String
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.optionTitle = optionTitle
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .appTypeface(.caption.weight(.semibold), size: 12, relativeTo: .caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            VirtualizedLoopingWheel(
                accessibilityLabel: title,
                selection: $selection,
                options: options,
                optionTitle: optionTitle
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .clipped()
    }
}

/// UIPickerView virtualizes its rows, unlike SwiftUI's wheel Picker which creates
/// every repeated Text child. A large logical row count therefore preserves the
/// clock-like looping gesture without rebuilding hundreds of SwiftUI views when a
/// neighboring setting changes.
private struct VirtualizedLoopingWheel<Selection: Hashable>: UIViewRepresentable {
    private static var cycleCount: Int { 10_001 }

    let accessibilityLabel: String
    @Binding var selection: Selection
    let options: [Selection]
    let optionTitle: (Selection) -> String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.accessibilityLabel = accessibilityLabel
        picker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        picker.setContentHuggingPriority(.defaultLow, for: .horizontal)
        context.coordinator.reloadAndSynchronize(picker, forceReload: true)
        return picker
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIPickerView,
        context: Context
    ) -> CGSize? {
        // Each wheel must use its HStack column's proposed width. UIKit's
        // intrinsic picker width otherwise pushes neighboring columns offscreen.
        CGSize(
            width: max(proposal.width ?? 0, 0),
            height: 216
        )
    }

    func updateUIView(_ picker: UIPickerView, context: Context) {
        let previousOptions = context.coordinator.parent.options
        context.coordinator.parent = self
        picker.accessibilityLabel = accessibilityLabel
        context.coordinator.reloadAndSynchronize(
            picker,
            forceReload: previousOptions != options
        )
    }

    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: VirtualizedLoopingWheel

        init(parent: VirtualizedLoopingWheel) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            max(pickerView.bounds.width - 16, 0)
        }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.options.count * VirtualizedLoopingWheel.cycleCount
        }

        func pickerView(
            _ pickerView: UIPickerView,
            viewForRow row: Int,
            forComponent component: Int,
            reusing view: UIView?
        ) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.adjustsFontForContentSizeCategory = true
            label.font = .preferredFont(forTextStyle: .title2)
            label.textAlignment = .center
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.68
            label.text = title(for: row)
            return label
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            guard !parent.options.isEmpty else { return }
            let offset = row % parent.options.count
            let value = parent.options[offset]
            if parent.selection != value {
                parent.selection = value
            }

            let lowerBoundary = parent.options.count * 2
            let upperBoundary = parent.options.count * (VirtualizedLoopingWheel.cycleCount - 2)
            if row < lowerBoundary || row >= upperBoundary {
                pickerView.selectRow(centeredRow(for: offset), inComponent: 0, animated: false)
            }
        }

        func reloadAndSynchronize(_ picker: UIPickerView, forceReload: Bool) {
            guard !parent.options.isEmpty else {
                if forceReload { picker.reloadAllComponents() }
                return
            }
            if forceReload { picker.reloadAllComponents() }

            let currentRow = picker.selectedRow(inComponent: 0)
            let currentOffset = currentRow >= 0 ? currentRow % parent.options.count : -1
            if currentOffset >= 0,
               parent.options[currentOffset] == parent.selection,
               !forceReload {
                return
            }

            let selectedOffset = parent.options.firstIndex(of: parent.selection) ?? 0
            picker.selectRow(centeredRow(for: selectedOffset), inComponent: 0, animated: false)
        }

        private func centeredRow(for offset: Int) -> Int {
            (VirtualizedLoopingWheel.cycleCount / 2) * parent.options.count + offset
        }

        private func title(for row: Int) -> String {
            guard !parent.options.isEmpty else { return "" }
            return parent.optionTitle(parent.options[row % parent.options.count])
        }
    }
}
