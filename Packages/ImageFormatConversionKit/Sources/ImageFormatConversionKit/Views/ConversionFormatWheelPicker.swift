//
//  文件职责：集中定义 ConversionFormatWheelPicker 相关的生产逻辑与共享能力。
//  所属模块：ImageFormatConversionKit。
//

import SwiftUI

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

/// Encapsulates the repeated-row representation used by a looping wheel.
/// Callers work with logical option offsets rather than repetition details.
private struct LoopingWheelIndexMap {
    let optionCount: Int
    private let cycleCount = 101

    var rowCount: Int {
        optionCount * cycleCount
    }

    func centeredIndex(for optionOffset: Int) -> Int {
        (cycleCount / 2) * optionCount + optionOffset
    }

    func optionOffset(for row: Int) -> Int {
        guard optionCount > 0 else { return 0 }
        return row % optionCount
    }

    func needsRecentering(_ row: Int) -> Bool {
        let lowerBoundary = optionCount * 2
        let upperBoundary = optionCount * (cycleCount - 2)
        return row < lowerBoundary || row >= upperBoundary
    }
}

/// 定义 `ConversionWheelColumn` 的值语义数据与相关行为。
struct ConversionWheelColumn<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [Selection]
    let optionTitle: (Selection) -> String
    @State private var wheelIndex: Int

    private var indexMap: LoopingWheelIndexMap {
        LoopingWheelIndexMap(optionCount: options.count)
    }

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

        let selectedOffset = options.firstIndex(of: selection.wrappedValue) ?? 0
        let indexMap = LoopingWheelIndexMap(optionCount: options.count)
        _wheelIndex = State(
            initialValue: options.isEmpty ? 0 : indexMap.centeredIndex(for: selectedOffset)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .appTypeface(.caption.weight(.semibold), size: 12, relativeTo: .caption, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Picker(title, selection: $wheelIndex) {
                if options.isEmpty {
                    Text("").tag(0)
                } else {
                    ForEach(0 ..< indexMap.rowCount, id: \.self) { index in
                        Text(optionTitle(options[indexMap.optionOffset(for: index)]))
                            .tag(index)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .onChange(of: wheelIndex) { _, newIndex in
                guard !options.isEmpty else { return }
                selection = options[indexMap.optionOffset(for: newIndex)]
                recenterIfNeeded(newIndex)
            }
            .onChange(of: selection) { _, newSelection in
                synchronizeWheel(with: newSelection)
            }
            .onChange(of: options) { _, _ in
                synchronizeWheel(with: selection, force: true)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func synchronizeWheel(with newSelection: Selection, force: Bool = false) {
        guard !options.isEmpty else { return }
        if !force,
           wheelIndex >= 0,
           wheelIndex < indexMap.rowCount,
           options[indexMap.optionOffset(for: wheelIndex)] == newSelection {
            return
        }
        let offset = options.firstIndex(of: newSelection) ?? 0
        let target = indexMap.centeredIndex(for: offset)
        guard wheelIndex != target else { return }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            wheelIndex = target
        }
    }

    private func recenterIfNeeded(_ index: Int) {
        guard !options.isEmpty else { return }
        guard indexMap.needsRecentering(index) else { return }

        let target = indexMap.centeredIndex(for: indexMap.optionOffset(for: index))
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            wheelIndex = target
        }
    }
}
