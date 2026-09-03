//
//  AppearanceThemeView.swift
//  CleanMyIPhone
//
//  应用外观与主题的统一设置页。
//  强调色与完整背景主题分别选择，避免业务页面直接拼装不协调的颜色 Token。
//

import SwiftUI

// MARK: - AppearanceThemeView

/// 展示即时主题预览、应用强调色、完整背景主题以及系统外观选择。
struct AppearanceThemeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var themeSettings: ThemeSettings

    /// 组合主题预览与三组低频全局设置，并沿用 App 的连续背景。
    var body: some View {
        List {
            previewSection
            accentPaletteSection
            backgroundPaletteSection
            if themeSettings.usesCustomBackground {
                customBackgroundEditorSection
            }
            glassCardSection
            glassTabSection
            displayOptionsSection
            fontSection
            appearanceSection
        }
        .contentMargins(.horizontal, 4, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .appSoftScrollEdge()
        .navigationTitle("Appearance & Theme")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: themeSettings.selectedAccentPaletteID)
        .sensoryFeedback(.selection, trigger: themeSettings.selectedThemeID)
        .sensoryFeedback(.selection, trigger: themeSettings.customBackgroundStyle.kind)
        .sensoryFeedback(.selection, trigger: themeSettings.liquidGlassCardsEnabled)
        .sensoryFeedback(.selection, trigger: themeSettings.liquidGlassTabEnabled)
    }

    /// 提供小型即时预览，使用户在离开设置页前理解配色关系。
    private var previewSection: some View {
        Section {
            AppearanceThemePreview()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    /// 展示有限且经过策划的强调色，避免任意颜色破坏控件对比度。
    private var accentPaletteSection: some View {
        Section {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(AppAccentPaletteID.allCases) { paletteID in
                            ThemePaletteSwatch(
                                title: paletteID.displayName,
                                sample: .accent(accentColor(for: paletteID)),
                                isSelected: themeSettings.selectedAccentPaletteID == paletteID
                            ) {
                                updateAccentPalette(paletteID)
                            }
                            .accessibilityIdentifier("appearance.accent.\(paletteID.rawValue)")
                        }
                    }
                    .padding(.vertical, 12)
                }

                Divider()

                ColorPicker(
                    "Edit App Color",
                    selection: customAccentBinding,
                    supportsOpacity: false
                )
                .frame(minHeight: 50)
                .accessibilityHint("Opens the system color picker and selects Custom.")
            }
        } header: {
            Text("App Color")
        } footer: {
            Text("Choose a preset or create any color with the system color picker.")
        }
        .appListCard()
    }

    /// 将背景作为完整 Theme 选择，确保文字、卡片、分隔线与系统明暗同步变化。
    private var backgroundPaletteSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(AppThemeID.allCases) { themeID in
                        ThemePaletteSwatch(
                            title: themeID.displayName,
                            sample: .background(themeID.theme),
                            isSelected: !themeSettings.usesCustomBackground
                                && themeSettings.selectedThemeID == themeID
                        ) {
                            updateBackgroundTheme(themeID)
                        }
                        .accessibilityIdentifier("appearance.background.\(themeID.rawValue)")
                    }

                    ThemePaletteSwatch(
                        title: "Custom",
                        sample: .background(themeSettings.customBackgroundTheme),
                        isSelected: themeSettings.usesCustomBackground
                    ) {
                        selectCustomBackground()
                    }
                    .accessibilityIdentifier("appearance.background.custom")
                }
                .padding(.vertical, 12)
            }
        } header: {
            Text("App Background")
        } footer: {
            Text("Custom backgrounds automatically derive readable text, cards, and dividers.")
        }
        .appListCard()
    }

    /// Keeps the advanced editor behind the existing Custom choice so the settings page stays calm.
    private var customBackgroundEditorSection: some View {
        Section {
            VStack(spacing: 16) {
                ThemeBackgroundLayer(background: themeSettings.customBackgroundTheme.background)
                    .frame(height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(theme.divider.opacity(0.7), lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)

                Divider()

                Picker("Background Style", selection: customBackgroundKindBinding) {
                    ForEach(AppCustomBackgroundKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance.background.style")

                Divider()

                switch themeSettings.customBackgroundStyle.kind {
                case .solid:
                    ColorPicker(
                        "Edit Background Color",
                        selection: customBackgroundBinding,
                        supportsOpacity: false
                    )
                    .frame(minHeight: 50)
                case .linear:
                    linearGradientEditor
                case .mesh:
                    meshGradientEditor
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Custom Background")
        } footer: {
            Text("The app automatically protects text contrast when custom colors are combined.")
        }
        .appListCard()
    }

    private var linearGradientEditor: some View {
        Group {
            Picker("Gradient Direction", selection: gradientDirectionBinding) {
                ForEach(AppLinearGradientDirection.allCases) { direction in
                    Text(direction.displayName).tag(direction)
                }
            }

            ForEach(Array(themeSettings.customBackgroundStyle.stops.enumerated()), id: \.element.id) {
                index,
                stop in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Color \(index + 1)")
                        Spacer()
                        ColorPicker(
                            "Color \(index + 1)",
                            selection: customColorBinding(for: stop),
                            supportsOpacity: false
                        )
                        .labelsHidden()

                        Button(role: .destructive) {
                            themeSettings.removeCustomGradientColor(stopID: stop.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(themeSettings.customBackgroundStyle.stops.count <= 2)
                        .accessibilityLabel("Remove Color")
                    }

                    HStack(spacing: 12) {
                        Text("Stop Position")
                            .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                            .foregroundStyle(theme.textSecondary)
                        Slider(value: customLocationBinding(for: stop), in: 0 ... 1)
                        Text(stop.location, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            if themeSettings.customBackgroundStyle.stops.count
                < AppCustomBackgroundStyle.maximumColorCount
            {
                Button {
                    themeSettings.addCustomGradientColor()
                } label: {
                    Label("Add Color", systemImage: "plus.circle")
                }
            }
        }
    }

    private var meshGradientEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Freeform Colors")
                .appTypeface(.subheadline.weight(.semibold), size: 15, relativeTo: .subheadline, weight: .semibold)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(Array(themeSettings.customBackgroundStyle.stops.prefix(9).enumerated()), id: \.element.id) {
                    index,
                    stop in
                    VStack(spacing: 5) {
                        ColorPicker(
                            "Color \(index + 1)",
                            selection: customColorBinding(for: stop),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(Text("Color \(index + 1)"))

                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 使用标准 Picker 表达互斥外观；固定明暗背景继续保护其既有对比关系。
    private var appearanceSection: some View {
        Section {
            if let fixedColorScheme = theme.preferredColorScheme {
                LabeledContent("Appearance") {
                    Text(fixedAppearanceName(for: fixedColorScheme))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Picker("Appearance", selection: $themeSettings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName)
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appearance.mode")
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text(appearanceFooter)
        }
        .appListCard()
    }

    /// Controls card material independently from the selected color palette.
    private var glassCardSection: some View {
        Section {
            Toggle(
                "Liquid Glass Cards",
                isOn: $themeSettings.liquidGlassCardsEnabled
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    themeSettings.liquidGlassCardsEnabled.toggle()
                }
            )
            .id(themeSettings.liquidGlassCardsEnabled)
            .accessibilityIdentifier("appearance.liquidGlass")
            .accessibilityValue(themeSettings.liquidGlassCardsEnabled ? "1" : "0")
        } header: {
            Text("Cards")
        } footer: {
            Text("Use system glass surfaces for content cards throughout the app.")
        }
        .appListCard()
    }

    /// Controls the primary navigation style independently from content cards.
    private var glassTabSection: some View {
        Section {
            Toggle(
                "Liquid Glass Tab",
                isOn: $themeSettings.liquidGlassTabEnabled
            )
            .accessibilityIdentifier("appearance.liquidGlassTab")
            .accessibilityValue(themeSettings.liquidGlassTabEnabled ? "1" : "0")
        } header: {
            Text("Tab Bar")
        } footer: {
            Text("Use the native Liquid Glass tab bar for primary navigation.")
        }
        .appListCard()
    }

    /// Groups optional presentation details without duplicating iOS Reduce Motion.
    private var displayOptionsSection: some View {
        Section {
            // One list row owns the glass surface; separate rows draw overlapping rounded edges.
            VStack(spacing: 0) {
                Toggle("Interface Animations", isOn: $themeSettings.interfaceAnimationsEnabled)
                    .accessibilityIdentifier("appearance.interfaceAnimations")
                    .frame(minHeight: 50)
                Divider()
                Toggle("Show Media Dates", isOn: $themeSettings.mediaDateHeadersEnabled)
                    .accessibilityIdentifier("appearance.mediaDates")
                    .frame(minHeight: 50)
            }
            .listRowSeparator(.hidden)
        } header: {
            Text("Display Options")
        } footer: {
            Text("Control dashboard animations, compression card animations, and date headings in media detail grids.")
        }
        .appListCard()
    }

    private var fontSection: some View {
        Section {
            Picker("appearance.font.title", selection: $themeSettings.fontStyle) {
                ForEach(AppFontStyle.availableCases) { style in
                    Text(LocalizedStringKey(style.titleKey)).tag(style)
                }
            }
            .accessibilityIdentifier("appearance.fontStyle")
        } header: {
            Text("appearance.font.title")
        } footer: {
            Text("appearance.font.languageNote")
        }
        .appListCard()
    }

    /// 自动强调色取自当前背景主题，其余选项使用自身的策划颜色。
    private func accentColor(for paletteID: AppAccentPaletteID) -> Color {
        switch paletteID {
        case .automatic:
            themeSettings.usesCustomBackground
                ? themeSettings.customBackgroundTheme.accentPrimary
                : themeSettings.selectedThemeID.theme.accentPrimary
        case .custom:
            themeSettings.customAccentColor.color
        default:
            paletteID.color ?? theme.accentPrimary
        }
    }

    /// 在减少动态效果开启时立即切换，否则仅做短促、可中断的颜色过渡。
    private func updateAccentPalette(_ paletteID: AppAccentPaletteID) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            themeSettings.selectAccentPalette(paletteID)
        }
    }

    /// 更新完整背景主题，避免只替换单个背景色造成层级失配。
    private func updateBackgroundTheme(_ themeID: AppThemeID) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            themeSettings.selectBackgroundTheme(themeID)
        }
    }

    /// 重新选择用户上次编辑的背景颜色，并保留预设主题以便随时切回。
    private func selectCustomBackground() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
            themeSettings.selectCustomBackground()
        }
    }

    /// 将系统 ColorPicker 的应用颜色变化写回可持久化的 sRGB 模型。
    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { themeSettings.accentPickerColor },
            set: { themeSettings.updateCustomAccentColor($0) }
        )
    }

    /// 将系统 ColorPicker 的背景颜色变化写回模型，并立即启用完整自定义主题。
    private var customBackgroundBinding: Binding<Color> {
        Binding(
            get: { themeSettings.backgroundPickerColor },
            set: { themeSettings.updateCustomBackgroundColor($0) }
        )
    }

    private var customBackgroundKindBinding: Binding<AppCustomBackgroundKind> {
        Binding(
            get: { themeSettings.customBackgroundStyle.kind },
            set: { kind in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    themeSettings.selectCustomBackgroundKind(kind)
                }
            }
        )
    }

    private var gradientDirectionBinding: Binding<AppLinearGradientDirection> {
        Binding(
            get: { themeSettings.customBackgroundStyle.direction },
            set: { themeSettings.updateCustomGradientDirection($0) }
        )
    }

    private func customColorBinding(for stop: AppBackgroundColorStop) -> Binding<Color> {
        Binding(
            get: {
                themeSettings.customBackgroundStyle.stops
                    .first(where: { $0.id == stop.id })?.color.color ?? stop.color.color
            },
            set: { themeSettings.updateCustomBackgroundColor($0, stopID: stop.id) }
        )
    }

    private func customLocationBinding(for stop: AppBackgroundColorStop) -> Binding<Double> {
        Binding(
            get: {
                themeSettings.customBackgroundStyle.stops
                    .first(where: { $0.id == stop.id })?.location ?? stop.location
            },
            set: { themeSettings.updateCustomGradientLocation($0, stopID: stop.id) }
        )
    }

    /// 说明当前 Appearance 是否可用，以及固定主题为何锁定明暗模式。
    private var appearanceFooter: LocalizedStringKey {
        theme.preferredColorScheme == nil
            ? "Choose the appearance used throughout the app."
            : "This background uses a fixed appearance to preserve contrast."
    }

    /// 将固定主题的实际明暗模式映射到本地化名称，而不是显示已被暂时覆盖的偏好值。
    private func fixedAppearanceName(for colorScheme: ColorScheme) -> LocalizedStringKey {
        colorScheme == .dark ? AppAppearance.dark.displayName : AppAppearance.light.displayName
    }
}

// MARK: - AppearanceThemePreview

/// 用最少元素预览背景、表面、文字、强调色和语义色之间的实际关系。
private struct AppearanceThemePreview: View {
    @Environment(\.appTheme) private var theme

    /// 绘制一个静态的存储摘要示例，避免预览读取真实媒体或文件数据。
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live Preview")
                        .appTypeface(.caption.weight(.semibold), size: 12, relativeTo: .caption, weight: .semibold)
                        .foregroundStyle(theme.textSecondary)
                    Text(verbatim: "CleanFile")
                        .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)
                        .foregroundStyle(theme.textPrimary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .appTypeface(.title2, size: 22, relativeTo: .title2, weight: .regular)
                    .foregroundStyle(theme.accentPrimary)
            }

            GeometryReader { proxy in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.accentPrimary)
                        .frame(width: proxy.size.width * 0.34)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.warningOrange.opacity(0.82))
                        .frame(width: proxy.size.width * 0.27)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.positiveGreen.opacity(0.78))
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(theme.textTertiary.opacity(0.35))
                        .frame(width: proxy.size.width * 0.18)
                }
            }
            .frame(height: 18)

            HStack(spacing: 8) {
                previewMetric(
                    title: "Media",
                    value: formattedByteCount(24_800_000_000),
                    color: theme.accentPrimary
                )
                previewMetric(
                    title: "Available",
                    value: formattedByteCount(18_200_000_000),
                    color: theme.positiveGreen
                )
            }
        }
        .padding(18)
        .appContentCard(cornerRadius: 24)
    }

    /// 构造带形状标记的示例指标，确保信息不只依赖颜色区分。
    private func previewMetric(title: LocalizedStringKey, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                    .foregroundStyle(theme.textTertiary)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 使用系统容量格式化器，让预览中的小数和单位跟随用户所在地区。
    private func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

// MARK: - ThemePaletteSwatch

/// 提供至少 44pt 的标准点击区域，并使用勾选、描边和文字共同表达选中状态。
private struct ThemePaletteSwatch: View {
    @Environment(\.appTheme) private var theme
    let title: LocalizedStringKey
    let sample: ThemePaletteSample
    let isSelected: Bool
    let action: () -> Void

    /// 显示颜色样本与名称；颜色不可辨识时仍可通过文字和勾选理解状态。
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                paletteSample

                Text(title)
                    .appTypeface(.caption2, size: 11, relativeTo: .caption2, weight: .regular)
                    .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 76)
            .frame(minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isSelected ? Text("Selected") : Text("Not Selected"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// 用不同样本区分单一强调色与成套背景主题，同时保持相同的触控和选中语义。
    @ViewBuilder
    private var paletteSample: some View {
        ZStack(alignment: .bottomTrailing) {
            switch sample {
            case let .accent(color):
                Circle()
                    .fill(color)
            case let .background(sampleTheme):
                ThemeBackgroundLayer(background: sampleTheme.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .center) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(sampleTheme.cardSurface)
                            .frame(width: 29, height: 24)
                            .overlay(alignment: .topLeading) {
                                Capsule()
                                    .fill(sampleTheme.textPrimary)
                                    .frame(width: 13, height: 3)
                                    .padding(6)
                            }
                    }
                    .overlay(alignment: .bottomLeading) {
                        Circle()
                            .fill(sampleTheme.accentPrimary)
                            .frame(width: 10, height: 10)
                            .padding(6)
                    }
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .appTypeface(.caption2.bold(), size: 11, relativeTo: .caption2, weight: .bold)
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 19, height: 19)
                    .background(theme.cardSurface, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.divider, lineWidth: 0.5)
                    }
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 48, height: 48)
        .overlay {
            RoundedRectangle(cornerRadius: sample.cornerRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? theme.accentPrimary : theme.divider,
                    lineWidth: isSelected ? 3 : 1
                )
                .padding(isSelected ? -4 : 0)
        }
    }
}

// MARK: - ThemePaletteSample

/// 描述调色盘中的视觉样本；背景选项携带完整 Theme，而不是退化成单一 Color。
private enum ThemePaletteSample {
    case accent(Color)
    case background(Theme)

    /// 为强调色使用圆形，为完整背景使用卡片形，帮助用户不依赖颜色理解两类选项。
    var cornerRadius: CGFloat {
        switch self {
        case .accent: 24
        case .background: 14
        }
    }
}

#if DEBUG
/// 在 Canvas 中使用隔离设置对象预览外观页，不污染用户的真实主题偏好。
#Preview("Appearance & Theme") {
    let defaults = UserDefaults(suiteName: "AppearanceThemePreview")!
    NavigationStack {
        AppearanceThemeView()
    }
    .environmentObject(ThemeSettings(userDefaults: defaults))
}
#endif
