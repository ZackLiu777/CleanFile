import SwiftUI

struct ConversionFormatOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let detail: String

    var id: Value { value }
}

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
