//
//  HelpView.swift
//  CleanMyIPhone
//
//  设置中的帮助首页。使用原生分组导航，保持内容在离线状态下也能完整阅读。
//

import SwiftUI

struct HelpView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                helpIntroduction

                ForEach(HelpCatalog.categories) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.title)
                            .appTypeface(.title3.weight(.bold), size: 20, relativeTo: .title3, weight: .bold)
                            .foregroundStyle(theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        categoryCard(category)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .appSoftScrollEdge()
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 将同一分类的文章组合成一张连续卡片，复用转换设置页的内容卡片层级。
    private func categoryCard(_ category: HelpCategory) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(category.articles.enumerated()), id: \.element.id) { index, article in
                NavigationLink {
                    HelpArticleView(article: article)
                } label: {
                    HStack(alignment: .center, spacing: 10) {
                        articleLabel(article)

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .appTypeface(.caption.weight(.semibold), size: 12, relativeTo: .caption, weight: .semibold)
                            .foregroundStyle(theme.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("help.article.\(article.id)")

                if index < category.articles.count - 1 {
                    Divider()
                        .overlay(theme.divider)
                        .padding(.leading, 62)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appContentCard(cornerRadius: 22)
    }

    private var helpIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .appTypeface(.system(size: 34, weight: .semibold), size: 34, relativeTo: .body, weight: .semibold)
                .foregroundStyle(theme.accentPrimary)
                .accessibilityHidden(true)

            Text("How can we help?")
                .appTypeface(.title2.bold(), size: 22, relativeTo: .title2, weight: .bold)
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Learn the app, understand what uses storage, and make careful cleanup decisions.")
                .appTypeface(.body, size: 17, relativeTo: .body, weight: .regular)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .appContentCard(cornerRadius: 22)
    }

    private func articleLabel(_ article: HelpArticle) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: article.systemImage)
                .appTypeface(.system(size: 17, weight: .semibold), size: 17, relativeTo: .body, weight: .semibold)
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(theme.accentPrimary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .appTypeface(.body.weight(.semibold), size: 17, relativeTo: .body, weight: .semibold)
                    .foregroundStyle(theme.textPrimary)

                Text(article.summary)
                    .appTypeface(.caption, size: 12, relativeTo: .caption, weight: .regular)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
