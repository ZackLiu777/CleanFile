import SwiftUI

@MainActor
struct ConversionReplacementReviewView: View {
    private enum Category: String, CaseIterable, Hashable {
        case image, video, audio

        var kind: ConversionMediaKind {
            switch self {
            case .image: .image
            case .video: .video
            case .audio: .audio
            }
        }

        var title: String {
            L10n.dynamicString("converter.mode.\(rawValue)")
        }

        var systemImage: String {
            switch self {
            case .image: "photo.on.rectangle.angled"
            case .video: "film.stack"
            case .audio: "waveform"
            }
        }
    }

    let candidates: [ConversionReplacementCandidate]
    let replace: ([ConversionReplacementCandidate]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conversionTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIDs: Set<UUID>
    @State private var selectedCategories: Set<Category>
    @State private var visibleCandidates: [ConversionReplacementCandidate]
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var hiddenIDs: Set<UUID> = []
    @State private var isConfirmationPresented = false
    @State private var isReplacing = false
    @State private var failurePresented = false
    @State private var pendingReplacementIDs: Set<UUID> = []
    @State private var categoryFrames: [String: CGRect] = [:]
    @State private var hiddenCategories: Set<Category> = []

    init(
        candidates: [ConversionReplacementCandidate],
        replace: @escaping ([ConversionReplacementCandidate]) async throws -> Void
    ) {
        self.candidates = candidates
        self.replace = replace
        _selectedIDs = State(initialValue: Set(candidates.map(\.id)))
        _selectedCategories = State(initialValue: Set(Category.allCases.filter { category in
            candidates.contains { $0.kind == category.kind }
        }))
        _visibleCandidates = State(initialValue: candidates)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    summaryCard
                    ForEach(Category.allCases, id: \.self) { category in
                        categoryCard(category)
                    }
                }
                .padding(16)
            }
            .converterSoftScrollEdge()
            .background(ConversionBackgroundView(background: theme.background).ignoresSafeArea())
            .navigationTitle(L10n.string("conversion.replace.review.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("action.cancel")) { dismiss() }
                        .disabled(isReplacing)
                }
                ToolbarItem(placement: .primaryAction) {
                    let available = Set(Category.allCases.filter { !candidates(in: $0).isEmpty })
                    let allSelected = !available.isEmpty && available.isSubset(of: selectedCategories)
                    Button(allSelected
                        ? L10n.string("conversion.replace.deselect_all")
                        : L10n.string("conversion.replace.select_all")) {
                        selectedCategories = allSelected ? [] : available
                        syncSelectedIDs()
                    }
                    .disabled(isReplacing)
                }
            }
            .safeAreaInset(edge: .bottom) { collectionReplacementBar }
        }
        .onPreferenceChange(ConversionReplacementFramePreferenceKey.self) { cardFrames = $0 }
        .onPreferenceChange(ConversionReplacementCategoryFramePreferenceKey.self) {
            categoryFrames = $0
        }
        .alert(L10n.string("conversion.replace.title"), isPresented: $isConfirmationPresented) {
            Button(L10n.string("action.cancel"), role: .cancel) {}
            Button(L10n.string("conversion.replace.action"), role: .destructive) {
                performReplacement()
            }
        } message: {
            Text(L10n.format("conversion.replace.message", pendingReplacementIDs.count))
        }
        .alert(L10n.string("conversion.replace.failed"), isPresented: $failurePresented) {
            Button(L10n.string("action.done")) {}
        }
    }

    private func candidates(in category: Category) -> [ConversionReplacementCandidate] {
        visibleCandidates.filter { $0.kind == category.kind }
    }

    private func categoryCard(_ category: Category) -> some View {
        let items = candidates(in: category)
        let bytes = items.reduce(Int64(0)) { $0 + max(0, $1.sourceBytes - $1.outputBytes) }
        let selected = selectedCategories.contains(category)
        return Button {
            guard !items.isEmpty else { return }
            if selected { selectedCategories.remove(category) }
            else { selectedCategories.insert(category) }
            syncSelectedIDs()
        } label: {
          HStack(spacing: 16) {
            Image(systemName: category.systemImage)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 58, height: 58)
                .background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(category.title)
                    .font(.headline)
                Text(categoryCount(category, count: items.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(selected ? theme.accent : .secondary)
          }
          .padding(16)
          .converterCard()
          .overlay {
              if selected {
                  RoundedRectangle(cornerRadius: 24, style: .continuous)
                      .stroke(theme.accent, lineWidth: 2)
              }
          }
          .opacity(hiddenCategories.contains(category) ? 0 : (items.isEmpty ? 0.55 : 1))
          .background {
              GeometryReader { proxy in
                  Color.clear.preference(
                      key: ConversionReplacementCategoryFramePreferenceKey.self,
                      value: [category.rawValue: proxy.frame(in: .global)]
                  )
              }
          }
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty || isReplacing)
    }

    private var collectionReplacementBar: some View {
        let selected = visibleCandidates.filter { candidate in
            selectedCategories.contains { $0.kind == candidate.kind }
        }
        let savings = selected.reduce(Int64(0)) { $0 + max(0, $1.sourceBytes - $1.outputBytes) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.format("conversion.replace.selected", selected.count))
                    .font(.subheadline.weight(.semibold))
                Text(ByteCountFormatter.string(fromByteCount: savings, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                pendingReplacementIDs = Set(selected.map(\.id))
                isConfirmationPresented = true
            } label: {
                if isReplacing { ProgressView() }
                else { Label(L10n.string("conversion.replace.action"), systemImage: "trash") }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selected.isEmpty || isReplacing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .converterCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func syncSelectedIDs() {
        selectedIDs = Set(visibleCandidates.filter { candidate in
            selectedCategories.contains { $0.kind == candidate.kind }
        }.map(\.id))
    }

    private func categoryDetail(_ category: Category) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                let items = candidates(in: category)
                if items.isEmpty {
                    ContentUnavailableView(
                        category.title,
                        systemImage: category.systemImage,
                        description: Text(L10n.string("conversion.replace.unavailable"))
                    )
                    .padding(.top, 80)
                } else {
                    ForEach(items) { candidate in
                        candidateCard(candidate)
                    }
                }
            }
            .padding(16)
        }
        .converterSoftScrollEdge()
        .background(ConversionBackgroundView(background: theme.background).ignoresSafeArea())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let ids = Set(candidates(in: category).map(\.id))
                let allSelected = !ids.isEmpty && ids.isSubset(of: selectedIDs)
                Button(allSelected
                    ? L10n.string("conversion.replace.deselect_all")
                    : L10n.string("conversion.replace.select_all")) {
                    if allSelected { selectedIDs.subtract(ids) }
                    else { selectedIDs.formUnion(ids) }
                }
                .disabled(ids.isEmpty || isReplacing)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !candidates(in: category).isEmpty {
                replacementBar(category: category)
            }
        }
    }

    private var selectedCandidates: [ConversionReplacementCandidate] {
        visibleCandidates.filter { selectedIDs.contains($0.id) }
    }

    private var selectedSavings: Int64 {
        selectedCandidates.reduce(0) { $0 + max(0, $1.sourceBytes - $1.outputBytes) }
    }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 48, height: 48)
                .background(.red.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("conversion.replace.review.summary"))
                    .font(.headline)
                Text(L10n.string("conversion.replace.review.detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .converterCard()
    }

    private func candidateCard(_ candidate: ConversionReplacementCandidate) -> some View {
        let selected = selectedIDs.contains(candidate.id)
        return Button {
            if selected { selectedIDs.remove(candidate.id) } else { selectedIDs.insert(candidate.id) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: candidate.kind == .image ? "photo" : "film")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 54, height: 54)
                    .background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.outputURL.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(sizeDetail(candidate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? theme.accent : .secondary)
            }
            .padding(14)
            .converterCard()
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(theme.accent, lineWidth: 2)
                }
            }
            .opacity(hiddenIDs.contains(candidate.id) ? 0 : 1)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ConversionReplacementFramePreferenceKey.self,
                        value: [candidate.id: proxy.frame(in: .global)]
                    )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isReplacing)
    }

    private func replacementBar(category: Category) -> some View {
        let categoryIDs = Set(candidates(in: category).map(\.id))
        let selectedCount = selectedIDs.intersection(categoryIDs).count
        let savings = candidates(in: category)
            .filter { selectedIDs.contains($0.id) }
            .reduce(Int64(0)) { $0 + max(0, $1.sourceBytes - $1.outputBytes) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.format("conversion.replace.selected", selectedCount))
                    .font(.subheadline.weight(.semibold))
                Text(ByteCountFormatter.string(fromByteCount: savings, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                pendingReplacementIDs = selectedIDs.intersection(categoryIDs)
                isConfirmationPresented = true
            } label: {
                if isReplacing { ProgressView() }
                else { Label(L10n.string("conversion.replace.action"), systemImage: "trash") }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedCount == 0 || isReplacing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .converterCard()
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func sizeDetail(_ candidate: ConversionReplacementCandidate) -> String {
        let source = ByteCountFormatter.string(fromByteCount: candidate.sourceBytes, countStyle: .file)
        let output = ByteCountFormatter.string(fromByteCount: candidate.outputBytes, countStyle: .file)
        return "\(source) → \(output)"
    }

    private func categoryCount(_ category: Category, count: Int) -> String {
        switch category {
        case .image: L10n.format("files.title", count)
        case .video: L10n.format("files.videos.title", count)
        case .audio: L10n.format("files.audio.title", count)
        }
    }

    private func performReplacement() {
        let selected = visibleCandidates.filter { pendingReplacementIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        isReplacing = true
        Task {
            do {
                try await replace(selected)
                await animateRemovedCategories(Set(selected.map(\.kind)))
                dismiss()
            } catch {
                isReplacing = false
                failurePresented = true
            }
        }
    }

    private func animateRemovedCategories(_ kinds: Set<ConversionMediaKind>) async {
#if os(iOS)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        let categories = Category.allCases.filter { kinds.contains($0.kind) }
        for category in categories {
            guard let frame = categoryFrames[category.rawValue],
                  let snapshot = ConversionReplacementCardDeletionEffect.capture(frame: frame, in: window)
            else { continue }
            await ConversionReplacementCardDeletionEffect.play(
                snapshot: snapshot,
                in: window,
                animated: !reduceMotion,
                hideOriginal: { hiddenCategories.insert(category) }
            )
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 220))
        }
#endif
    }

    private func animateRemoved(_ ids: [UUID]) async {
#if os(iOS)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return }
        for id in ids {
            guard let frame = cardFrames[id],
                  let snapshot = ConversionReplacementCardDeletionEffect.capture(frame: frame, in: window)
            else { continue }
            await ConversionReplacementCardDeletionEffect.play(
                snapshot: snapshot,
                in: window,
                animated: !reduceMotion,
                hideOriginal: { hiddenIDs.insert(id) }
            )
            withAnimation(.snappy(duration: reduceMotion ? 0.16 : 0.32)) {
                visibleCandidates.removeAll { $0.id == id }
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 220))
        }
#endif
    }
}
