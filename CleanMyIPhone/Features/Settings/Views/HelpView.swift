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
        List {
            Section {
                helpIntroduction
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(HelpCatalog.categories) { category in
                Section {
                    ForEach(category.articles) { article in
                        NavigationLink {
                            HelpArticleView(article: article)
                        } label: {
                            articleLabel(article)
                        }
                        .accessibilityIdentifier("help.article.\(article.id)")
                    }
                } header: {
                    Text(category.title)
                        .accessibilityAddTraits(.isHeader)
                }
                .appListCard()
            }
        }
        .contentMargins(.horizontal, 4, for: .scrollContent)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .appSoftScrollEdge()
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var helpIntroduction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.accentPrimary)
                .accessibilityHidden(true)

            Text("How can we help?")
                .font(.title2.bold())
                .foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Learn the app, understand what uses storage, and make careful cleanup decisions.")
                .font(.body)
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(theme.accentPrimary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(article.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)

                Text(article.summary)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
    }
}
