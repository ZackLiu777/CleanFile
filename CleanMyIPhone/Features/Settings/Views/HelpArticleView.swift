//
//  HelpArticleView.swift
//  CleanMyIPhone
//
//  呈现单篇本地帮助文章、操作步骤和 Apple 官方延伸阅读。
//

import Foundation
import SwiftUI

struct HelpArticleView: View {
    @Environment(\.appTheme) private var theme

    let article: HelpArticle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                articleHeader

                if let notice = article.notice {
                    noticeCard(notice)
                }

                ForEach(article.sections) { section in
                    sectionCard(section)
                }

                if !article.resources.isEmpty {
                    resourcesCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .appSoftScrollEdge()
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: article.systemImage)
                .appTypeface(.system(size: 28, weight: .semibold), size: 28, relativeTo: .body, weight: .semibold)
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 52, height: 52)
                .background(theme.accentPrimary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            Text(article.title)
                .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(article.summary)
                .appTypeface(.body, size: 17, relativeTo: .body, weight: .regular)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appContentCard(cornerRadius: 22)
    }

    private func noticeCard(_ notice: HelpNotice) -> some View {
        let color = noticeColor(for: notice.tone)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: noticeSymbol(for: notice.tone))
                .appTypeface(.system(size: 18, weight: .semibold), size: 18, relativeTo: .body, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(notice.title)
                    .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text(notice.detail)
                    .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(color.opacity(0.24), lineWidth: 0.75)
        }
    }

    private func sectionCard(_ section: HelpArticleSection) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .appTypeface(.body, size: 17, relativeTo: .body, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(section.steps.enumerated()), id: \.element.id) { index, step in
                if index > 0 || !section.paragraphs.isEmpty {
                    Divider()
                        .overlay(theme.divider)
                }

                stepRow(step, number: index + 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appContentCard(cornerRadius: 20)
    }

    private func stepRow(_ step: HelpStep, number: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 28, height: 28)
                .background(theme.accentPrimary.opacity(0.12), in: Circle())
                .accessibilityLabel(Text("Step \(number)"))

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .appTypeface(.body.weight(.semibold), size: 17, relativeTo: .body, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.detail)
                    .appTypeface(.subheadline, size: 15, relativeTo: .subheadline, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var resourcesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apple Support Resources")
                .appTypeface(.headline, size: 17, relativeTo: .headline, weight: .semibold)
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(article.resources.enumerated()), id: \.element.id) { index, resource in
                if index > 0 {
                    Divider()
                        .overlay(theme.divider)
                }

                if let url = URL(string: resource.urlString) {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .foregroundStyle(theme.accentPrimary)
                                .frame(width: 24)
                                .accessibilityHidden(true)

                            Text(resource.title)
                                .appTypeface(.body, size: 17, relativeTo: .body, weight: .regular)
                                .foregroundStyle(theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.right")
                                .appTypeface(.caption.bold(), size: 12, relativeTo: .caption, weight: .bold)
                                .foregroundStyle(theme.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("help.resource.\(article.id).\(resource.id)")
                    .accessibilityHint("Opens Apple Support in your browser.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appContentCard(cornerRadius: 20)
    }

    private func noticeColor(for tone: HelpNotice.Tone) -> Color {
        switch tone {
        case .information:
            theme.accentPrimary
        case .caution:
            theme.warningOrange
        case .privacy:
            theme.positiveGreen
        }
    }

    private func noticeSymbol(for tone: HelpNotice.Tone) -> String {
        switch tone {
        case .information:
            "info.circle.fill"
        case .caution:
            "exclamationmark.triangle.fill"
        case .privacy:
            "lock.shield.fill"
        }
    }
}
