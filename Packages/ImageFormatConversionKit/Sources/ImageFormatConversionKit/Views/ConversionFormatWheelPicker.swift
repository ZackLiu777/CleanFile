// 转换设置的多列滚轮与弹出面板。
// 泛型列通过绑定传递选中值，UIKit 滚轮负责循环显示并同步外部选择。
// 具体格式和取值由各转换页面提供，不在此组件中修改转换任务。
// 每列根据选项循环显示逻辑行，并在绑定或选项变化时同步当前位置。
// 滚轮仅回写用户选择，不检查编码器是否支持最终的参数组合。

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

/// 定义设置滚轮入口的按压高亮样式。
private struct ConversionSettingsTriggerButtonStyle: ButtonStyle {
    let accent: Color

    /// 在按压时以主题强调色突出按钮区域。
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

/// 将一组可选值和绑定选择包装为滚轮列，标题由调用方提供。
struct ConversionWheelColumn<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let optionTitle: (Selection) -> String

    /// 设置列标题、选中值绑定、可选项与标题格式化方式。
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

    /// 创建桥接 SwiftUI 绑定与 UIKit 滚轮代理的协调器。
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// 创建滚轮并连接数据源、代理、无障碍标签和初始选中状态。
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

    /// 使用父布局建议的列宽及固定高度，避免 UIKit 固有宽度挤压相邻列。
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

    /// 同步最新绑定和选项；选项变化时重新加载并定位选中值。
    func updateUIView(_ picker: UIPickerView, context: Context) {
        let previousOptions = context.coordinator.parent.options
        context.coordinator.parent = self
        picker.accessibilityLabel = accessibilityLabel
        context.coordinator.reloadAndSynchronize(
            picker,
            forceReload: previousOptions != options
        )
    }

    /// 提供循环滚轮的数据源、选中回写和边界重定位。
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        var parent: VirtualizedLoopingWheel

        /// 保存当前 SwiftUI 滚轮配置，后续更新时由代表视图替换。
        init(parent: VirtualizedLoopingWheel) {
            self.parent = parent
        }

        /// 每个滚轮实例只展示一列。
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

        /// 根据滚轮实际宽度计算列宽，并预留左右空间。
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            max(pickerView.bounds.width - 16, 0)
        }

        /// 将选项重复为大量逻辑行，供 UIKit 按需显示以模拟循环。
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            parent.options.count * VirtualizedLoopingWheel.cycleCount
        }

        /// 复用标签显示对应选项，并适配系统文字大小。
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

        /// 将逻辑行映射回选项并更新绑定；靠近边界时无动画移回中间周期。
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

        /// 在选项或绑定变化后刷新并将滚轮定位到对应值。
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

        /// 计算指定选项在中间周期中的行号，保留两个方向的滚动余量。
        private func centeredRow(for offset: Int) -> Int {
            (VirtualizedLoopingWheel.cycleCount / 2) * parent.options.count + offset
        }

        /// 通过取模将逻辑行映射到实际选项，空列表返回空标题。
        private func title(for row: Int) -> String {
            guard !parent.options.isEmpty else { return "" }
            return parent.optionTitle(parent.options[row % parent.options.count])
        }
    }
}
